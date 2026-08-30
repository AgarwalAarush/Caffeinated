import SwiftUI

struct StatsView: View {
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        let snap = monitor.snapshot
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.horizontal, 10)
            meters(snap)
            Divider().padding(.horizontal, 10)
            battery(snap)
        }
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }

    private var header: some View {
        HStack {
            Text("Stats")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text("live")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func meters(_ snap: SystemSnapshot) -> some View {
        VStack(spacing: 8) {
            MeterRow(
                title: "CPU",
                detail: String(format: "%.0f%%", snap.cpuPercent),
                fraction: snap.cpuPercent / 100
            )
            MeterRow(
                title: "GPU",
                detail: snap.gpuPercent.map { String(format: "%.0f%%", $0) } ?? "—",
                fraction: (snap.gpuPercent ?? 0) / 100
            )
            MeterRow(
                title: "Memory",
                detail: "\(ByteFormat.bytes(snap.memoryUsedBytes)) / \(ByteFormat.bytes(snap.memoryTotalBytes))",
                fraction: snap.memoryUsedFraction,
                tone: pressureColor(snap.memoryPressure)
            )
            MeterRow(
                title: "Storage",
                detail: "\(ByteFormat.bytes(snap.diskUsedBytes)) / \(ByteFormat.bytes(snap.diskTotalBytes))",
                fraction: snap.diskUsedFraction
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func battery(_ snap: SystemSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Battery")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if let percent = snap.batteryPercent {
                    Text(String(format: "%.0f%%", percent))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
            }

            if let percent = snap.batteryPercent {
                MeterBar(fraction: percent / 100, tone: batteryTone(percent, charging: snap.batteryIsCharging))
            }

            HStack {
                Text(batteryStateLabel(snap))
                Spacer()
                if let minutes = snap.batteryTimeRemainingMinutes {
                    Text(minutesLabel(minutes))
                        .monospacedDigit()
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                statChip("Health", snap.batteryHealthPercent.map { String(format: "%.0f%%", $0) } ?? "—")
                statChip("Cycles", snap.batteryCycleCount.map(String.init) ?? "—")
                statChip("Power", snap.batteryWatts.map { String(format: "%.1f W", $0) } ?? "—")
                if let temp = snap.batteryTemperatureC, temp > 0, temp < 80 {
                    statChip("Temp", String(format: "%.0f°", temp))
                }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private func statChip(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func batteryStateLabel(_ snap: SystemSnapshot) -> String {
        if snap.batteryPercent == nil { return "No battery" }
        if snap.batteryIsCharging { return "Charging" }
        if snap.batteryOnAC { return "On Power Adapter" }
        return "On Battery"
    }

    private func minutesLabel(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
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
    let title: String
    let detail: String
    let fraction: Double
    var tone: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text(detail)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            MeterBar(fraction: fraction, tone: tone)
        }
    }
}

private struct MeterBar: View {
    let fraction: Double
    var tone: Color = .accentColor

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.12))
                Capsule()
                    .fill(tone)
                    .frame(width: max(4, geo.size.width * max(0, min(1, fraction))))
            }
        }
        .frame(height: 6)
    }
}
