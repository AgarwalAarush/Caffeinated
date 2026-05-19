import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var manager: CaffeinateManager
    @Environment(\.openURL) private var openURL
    @StateObject private var loginController = LaunchAtLoginController()
    @State private var durationExpanded: Bool = true
    @State private var settingsExpanded: Bool = false

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
            .toggleStyle(PillToggleStyle())
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
            MenuRow(
                title: "Settings",
                trailing: .chevron,
                chevronRotation: settingsExpanded ? 90 : 0
            ) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    settingsExpanded.toggle()
                }
            }

            if settingsExpanded {
                settingsBody
                    .transition(.opacity.combined(with: .move(edge: .top)))
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
        .onAppear { loginController.refresh() }
    }

    private var settingsBody: some View {
        VStack(spacing: 0) {
            settingsRow("Open at Login", isOn: $loginController.isEnabled)
            settingsRow("Pause on Battery", isOn: $manager.pauseOnBattery)
            settingsRow("Notify When Timer Ends", isOn: $manager.notifyOnTimerEnd)
        }
        .padding(.bottom, 2)
    }

    private func settingsRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(PillToggleStyle(width: 30, height: 18))
        }
        .padding(.horizontal, 26)
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
    var chevronRotation: Double = 0
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
                        .rotationEffect(.degrees(chevronRotation))
                        .animation(.easeInOut(duration: 0.18), value: chevronRotation)
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

// MARK: - Pill Toggle Style (iOS-style switch)

struct PillToggleStyle: ToggleStyle {
    var onColor: Color = .accentColor
    var offColor: Color = Color.secondary.opacity(0.28)
    var width: CGFloat = 38
    var height: CGFloat = 22

    func makeBody(configuration: Configuration) -> some View {
        let knob = height - 4
        let travel = (width - height) / 2

        return HStack {
            configuration.label
            ZStack {
                Capsule()
                    .fill(configuration.isOn ? onColor : offColor)
                Circle()
                    .fill(Color.white)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                    .offset(x: configuration.isOn ? travel : -travel)
            }
            .frame(width: width, height: height)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: configuration.isOn)
            .contentShape(Capsule())
            .onTapGesture {
                configuration.isOn.toggle()
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(CaffeinateManager())
}
