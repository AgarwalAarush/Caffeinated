import SwiftUI

struct StatsView: View {
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        let snap = monitor.snapshot
        VStack(alignment: .leading, spacing: 0) {
            meters(snap)
            Divider().padding(.horizontal, 10)
            battery(snap)
        }
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }

    private func meters(_ snap: SystemSnapshot) -> some View {
        VStack(spacing: 12) {
            MeterRow(
                symbol: "cpu",
                title: "CPU",
                detail: snap.cpuReady ? String(format: "%.0f%%", snap.cpuPercent) : "—",
                fraction: snap.cpuReady ? snap.cpuPercent / 100 : 0,
                tone: loadTone(snap.cpuReady ? snap.cpuPercent : nil)
            )
            MeterRow(
                symbol: "gpu",
                title: "GPU",
                detail: snap.gpuPercent.map { String(format: "%.0f%%", $0) } ?? "n/a",
                fraction: (snap.gpuPercent ?? 0) / 100,
                tone: loadTone(snap.gpuPercent),
                showFill: snap.gpuPercent != nil
            )
            MeterRow(
                symbol: "memorychip",
                title: "Memory",
                detail: ByteFormat.memoryPair(used: snap.memoryUsedBytes, total: snap.memoryTotalBytes),
                fraction: snap.memoryUsedFraction,
                tone: pressureColor(snap.memoryPressure)
            )
            MeterRow(
                symbol: "internaldrive",
                title: "Storage",
                detail: storageFreeLabel(snap),
                fraction: snap.diskUsedFraction,
                tone: diskTone(snap.diskUsedFraction)
            )
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    private func battery(_ snap: SystemSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: batterySymbol(snap))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(batteryIconColor(snap))
                    .frame(width: 16)
                Text("Battery")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if let percent = snap.batteryPercent {
                    Text(String(format: "%.0f%%", percent))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }

            if snap.batteryPercent == nil {
                Text("This Mac has no battery.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                if let percent = snap.batteryPercent {
                    MeterBar(
                        fraction: percent / 100,
                        tone: batteryTone(percent, charging: snap.batteryIsCharging)
                    )
                }

                Text(batteryStateLabel(snap))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    statChip("Health", snap.batteryHealthPercent.map { String(format: "%.0f%%", $0) } ?? "—")
                    statChip("Cycles", snap.batteryCycleCount.map { $0.formatted() } ?? "—")
                    statChip("Power", powerLabel(snap))
                    if let temp = snap.batteryTemperatureC, temp > 0, temp < 80 {
                        statChip("Temp", String(format: "%.0f°C", temp))
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private func statChip(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
        )
    }

    private func storageFreeLabel(_ snap: SystemSnapshot) -> String {
        guard snap.diskTotalBytes >= snap.diskUsedBytes else { return "—" }
        let free = snap.diskTotalBytes - snap.diskUsedBytes
        return "\(ByteFormat.bytes(free)) free"
    }

    private func powerLabel(_ snap: SystemSnapshot) -> String {
        guard let watts = snap.batteryWatts else { return "—" }
        let mag = String(format: "%.1f W", abs(watts))
        if snap.batteryIsCharging || watts > 0.15 { return "+\(mag)" }
        if watts < -0.15 { return "−\(mag)" }
        return mag
    }

    private func batteryStateLabel(_ snap: SystemSnapshot) -> String {
        let remaining: String? = snap.batteryTimeRemainingMinutes.map { minutesLabel($0) }
        if snap.batteryIsCharging {
            if let remaining { return "Charging · \(remaining) to full" }
            return "Charging"
        }
        if snap.batteryOnAC {
            return remaining.map { "On adapter · \($0) remaining" } ?? "On Power Adapter"
        }
        if let remaining { return "On battery · \(remaining) left" }
        return "On Battery"
    }

    private func minutesLabel(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private func batterySymbol(_ snap: SystemSnapshot) -> String {
        if snap.batteryPercent == nil { return "battery.slash" }
        if snap.batteryIsCharging { return "battery.100percent.bolt" }
        let percent = snap.batteryPercent ?? 0
        switch percent {
        case 90...: return "battery.100percent"
        case 65..<90: return "battery.75percent"
        case 40..<65: return "battery.50percent"
        case 15..<40: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    private func batteryIconColor(_ snap: SystemSnapshot) -> Color {
        if snap.batteryPercent == nil { return .secondary }
        if snap.batteryIsCharging { return .accentColor }
        if let percent = snap.batteryPercent, percent <= 20 { return .red }
        return .primary
    }

    private func loadTone(_ percent: Double?) -> Color {
        guard let percent else { return Color.secondary.opacity(0.35) }
        if percent >= 90 { return .red }
        if percent >= 75 { return .orange }
        return .accentColor
    }

    private func diskTone(_ fraction: Double) -> Color {
        if fraction >= 0.9 { return .red }
        if fraction >= 0.8 { return .orange }
        return .accentColor
    }

    private func pressureColor(_ pressure: SystemSnapshot.MemoryPressure) -> Color {
        switch pressure {
        case .ok: return .accentColor
        case .caution: return .orange
        case .urgent: return .red
        }
    }

    private func batteryTone(_ percent: Double, charging: Bool) -> Color {
        if charging { return .accentColor }
        if percent <= 20 { return .red }
        if percent <= 40 { return .orange }
        return .accentColor
    }
}

private struct MeterRow: View {
    let symbol: String
    let title: String
    let detail: String
    let fraction: Double
    var tone: Color = .accentColor
    var showFill: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(detail)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            MeterBar(fraction: fraction, tone: tone, showFill: showFill)
                .padding(.leading, 24)
        }
    }
}

private struct MeterBar: View {
    let fraction: Double
    var tone: Color = .accentColor
    var showFill: Bool = true

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.12))
                if showFill {
                    Capsule()
                        .fill(tone)
                        .frame(width: max(4, geo.size.width * max(0, min(1, fraction))))
                        .animation(.easeInOut(duration: 0.35), value: fraction)
                }
            }
        }
        .frame(height: 6)
    }
}
