import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var manager: CaffeinateManager
    @Environment(\.openURL) private var openURL
    @State private var durationExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.horizontal, 10)
            durationSection
            Divider().padding(.horizontal, 10)
            footer
        }
        .frame(width: 260)
        .padding(.vertical, 6)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text("Caffeinated")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Toggle("", isOn: Binding(
                get: { manager.isActive },
                set: { manager.setActive($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(.accentColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    durationExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("Duration")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(durationExpanded ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            if durationExpanded {
                HStack(spacing: 4) {
                    ForEach(Array(CaffeinateDuration.presets.enumerated()), id: \.element.id) { index, duration in
                        DurationPill(
                            duration: duration,
                            isSelected: manager.selectedDuration == duration
                        ) {
                            manager.selectDuration(duration)
                        }
                        if index == 0 {
                            Text("·")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary.opacity(0.6))
                                .padding(.horizontal, 1)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            MenuRow(title: "Settings", trailing: .chevron) {
                // Reserved for future preferences (launch at login, etc.)
            }
            MenuRow(title: "About") {
                if let url = URL(string: "https://github.com/AgarwalAarush/Caffeinated") {
                    openURL(url)
                }
            }
            MenuRow(title: "Quit") {
                NSApp.terminate(nil)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Duration Pill

private struct DurationPill: View {
    let duration: CaffeinateDuration
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.secondary.opacity(0.12)))
                    .frame(width: 26, height: 26)
                content
            }
            .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    @ViewBuilder
    private var content: some View {
        switch duration {
        case .indefinite:
            Image(systemName: "infinity")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        case .minutes, .hours:
            Text(duration.label)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
    }

    private var helpText: String {
        switch duration {
        case .indefinite: return "Stay awake until turned off"
        case .minutes(let m): return "\(m) minutes"
        case .hours(let h): return h == 1 ? "1 hour" : "\(h) hours"
        }
    }
}

// MARK: - Menu Row

private struct MenuRow: View {
    enum Trailing {
        case none
        case chevron
    }

    let title: String
    var trailing: Trailing = .none
    let action: () -> Void

    @State private var hovering: Bool = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                Spacer()
                if case .chevron = trailing {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(hovering ? Color.accentColor.opacity(0.85) : Color.clear)
                    .padding(.horizontal, 6)
            )
            .foregroundStyle(hovering ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

#Preview {
    ContentView()
        .environmentObject(CaffeinateManager())
}
