import Foundation
import Combine
import IOKit
import IOKit.ps
import Darwin

struct SystemSnapshot: Equatable {
    var cpuPercent: Double = 0
    var gpuPercent: Double?
    var cpuReady: Bool = false
    var memoryUsedBytes: UInt64 = 0
    var memoryTotalBytes: UInt64 = 0
    var memoryPressure: MemoryPressure = .ok
    var diskUsedBytes: UInt64 = 0
    var diskTotalBytes: UInt64 = 0
    var batteryPercent: Double?
    var batteryHealthPercent: Double?
    var batteryCycleCount: Int?
    /// Signed: negative while discharging.
    var batteryWatts: Double?
    var batteryIsCharging: Bool = false
    var batteryOnAC: Bool = false
    var batteryTimeRemainingMinutes: Int?
    var batteryTemperatureC: Double?
    var sampledAt: Date = .distantPast

    enum MemoryPressure: String {
        case ok, caution, urgent
    }

    var memoryUsedFraction: Double {
        guard memoryTotalBytes > 0 else { return 0 }
        return min(1, Double(memoryUsedBytes) / Double(memoryTotalBytes))
    }

    var diskUsedFraction: Double {
        guard diskTotalBytes > 0 else { return 0 }
        return min(1, Double(diskUsedBytes) / Double(diskTotalBytes))
    }
}

/// Samples CPU, GPU, memory, disk and battery on a 1s timer while the Stats
/// tab is visible. Cheap IOKit / Mach reads — nothing polls `powermetrics`.
final class SystemMonitor: ObservableObject {
    @Published private(set) var snapshot = SystemSnapshot()
    @Published private(set) var isRunning = false

    private var timer: Timer?
    private var previousCPU: host_cpu_load_info = host_cpu_load_info()
    private var hasPreviousCPU = false

    func start() {
        guard !isRunning else { return }
        isRunning = true
        refresh()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        hasPreviousCPU = false
        snapshot.cpuReady = false
    }

    func refresh() {
        var next = snapshot
        next.sampledAt = Date()

        if let load = Self.cpuLoad() {
            if hasPreviousCPU {
                next.cpuPercent = Self.cpuPercent(from: previousCPU, to: load)
                next.cpuReady = true
            }
            previousCPU = load
            hasPreviousCPU = true
        }

        next.gpuPercent = Self.gpuPercent()
        Self.readMemory(&next)
        Self.readDisk(&next)
        Self.readBattery(&next)
        snapshot = next
    }

    // MARK: - CPU

    private static func cpuLoad() -> host_cpu_load_info? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        return info
    }

    private static func cpuPercent(from old: host_cpu_load_info, to new: host_cpu_load_info) -> Double {
        let user = Double(new.cpu_ticks.0 &- old.cpu_ticks.0)
        let system = Double(new.cpu_ticks.1 &- old.cpu_ticks.1)
        let idle = Double(new.cpu_ticks.2 &- old.cpu_ticks.2)
        let nice = Double(new.cpu_ticks.3 &- old.cpu_ticks.3)
        let total = user + system + idle + nice
        guard total > 0 else { return 0 }
        return min(100, max(0, (user + system + nice) / total * 100))
    }

    // MARK: - GPU

    private static func gpuPercent() -> Double? {
        let matching = IOServiceMatching("IOAccelerator")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var best: Double?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            var unmanaged: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = unmanaged?.takeRetainedValue() as? [String: Any],
                  let stats = props["PerformanceStatistics"] as? [String: Any] else {
                continue
            }
            let keys = [
                "Device Utilization %",
                "In Use Device Utilization %",
                "GPU Core Utilization",
                "Renderer Utilization %",
                "Tiler Utilization %"
            ]
            for key in keys {
                if let value = number(stats[key]) {
                    best = max(best ?? 0, min(100, value))
                    break
                }
            }
        }
        return best
    }

    // MARK: - Memory

    private static func readMemory(_ snapshot: inout SystemSnapshot) {
        snapshot.memoryTotalBytes = ProcessInfo.processInfo.physicalMemory

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<natural_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return }

        let page = UInt64(vm_kernel_page_size)
        let active = UInt64(stats.active_count) * page
        let wired = UInt64(stats.wire_count) * page
        let compressed = UInt64(stats.compressor_page_count) * page
        let speculative = UInt64(stats.speculative_count) * page
        let free = UInt64(stats.free_count) * page

        let used = min(snapshot.memoryTotalBytes, active + wired + compressed)
        snapshot.memoryUsedBytes = used

        // Compressed memory is normal on macOS; only tint the bar when
        // free pages are actually scarce.
        let freeish = Double(free + speculative) / Double(max(1, snapshot.memoryTotalBytes))
        if freeish < 0.04 {
            snapshot.memoryPressure = .urgent
        } else if freeish < 0.08 {
            snapshot.memoryPressure = .caution
        } else {
            snapshot.memoryPressure = .ok
        }
    }

    // MARK: - Disk

    private static func readDisk(_ snapshot: inout SystemSnapshot) {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]) else { return }
        let total = UInt64(values.volumeTotalCapacity ?? 0)
        let available = UInt64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        snapshot.diskTotalBytes = total
        if total >= available {
            snapshot.diskUsedBytes = total - available
        }
    }

    // MARK: - Battery / power

    private static func readBattery(_ snapshot: inout SystemSnapshot) {
        snapshot.batteryOnAC = !isOnBattery()

        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
            for source in list {
                guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else {
                    continue
                }
                let type = desc[kIOPSTypeKey as String] as? String
                guard type == (kIOPSInternalBatteryType as String) || desc[kIOPSIsPresentKey as String] as? Bool == true else {
                    continue
                }
                if let current = number(desc[kIOPSCurrentCapacityKey as String]),
                   let max = number(desc[kIOPSMaxCapacityKey as String]), max > 0 {
                    snapshot.batteryPercent = current / max * 100
                }
                snapshot.batteryIsCharging = (desc[kIOPSIsChargingKey as String] as? Bool) ?? false
                if let minutes = desc[kIOPSTimeToEmptyKey as String] as? Int, minutes > 0, minutes < 20_000 {
                    snapshot.batteryTimeRemainingMinutes = minutes
                } else if let minutes = desc[kIOPSTimeToFullChargeKey as String] as? Int, minutes > 0, minutes < 20_000 {
                    snapshot.batteryTimeRemainingMinutes = minutes
                }
            }
        }

        let matching = IOServiceMatching("AppleSmartBattery")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = unmanaged?.takeRetainedValue() as? [String: Any] else {
            return
        }

        if let cycles = intNumber(props["CycleCount"]) {
            snapshot.batteryCycleCount = cycles
        }

        let design = number(props["DesignCapacity"])
        let maxCap = number(props["AppleRawMaxCapacity"]) ?? number(props["MaxCapacity"])
        if let design, let maxCap, design > 0 {
            snapshot.batteryHealthPercent = min(100, maxCap / design * 100)
        }

        let voltage_mV = number(props["Voltage"])
        let amperage_mA = number(props["InstantAmperage"]) ?? number(props["Amperage"])
        if let voltage_mV, let amperage_mA {
            // InstantAmperage is signed: negative while discharging.
            var milliamps = amperage_mA
            if milliamps > 32767 { milliamps -= 65536 } // 16-bit two's complement packed in a larger int
            snapshot.batteryWatts = (voltage_mV * milliamps) / 1_000_000
        } else if let adapter = props["AdapterDetails"] as? [String: Any],
                  let watts = number(adapter["Watts"]) {
            snapshot.batteryWatts = watts
        }

        if let rawTemp = number(props["Temperature"]) {
            if rawTemp > 200 {
                snapshot.batteryTemperatureC = rawTemp / 100
            } else {
                snapshot.batteryTemperatureC = rawTemp / 10
            }
        }
    }

    private static func isOnBattery() -> Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return false }
        let type = IOPSGetProvidingPowerSourceType(blob).takeUnretainedValue() as String
        return type == (kIOPSBatteryPowerValue as String)
    }

    private static func number(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let i = any as? Int64 { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        return nil
    }

    private static func intNumber(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        if let d = any as? Double { return Int(d) }
        return nil
    }
}

enum ByteFormat {
    static func bytes(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        let gb = 1_073_741_824.0
        if value >= gb {
            return String(format: "%.1f GB", value / gb)
        }
        let mb = 1_048_576.0
        return String(format: "%.0f MB", value / mb)
    }

    /// Compact used/total pair for the memory meter, e.g. `12.4/16 GB`.
    static func memoryPair(used: UInt64, total: UInt64) -> String {
        let gb = 1_073_741_824.0
        if Double(total) >= gb {
            return String(format: "%.1f/%.0f GB", Double(used) / gb, Double(total) / gb)
        }
        return "\(bytes(used))/\(bytes(total))"
    }
}
