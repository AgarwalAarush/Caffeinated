import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var manager: CaffeinateManager
    @EnvironmentObject private var updates: UpdateChecker
    @Environment(\.openURL) private var openURL
    @StateObject private var loginController = LaunchAtLoginController()
    @State private var durationExpanded: Bool = true
    @State private var settingsExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            durationSection
            Divider().padding(.horizontal, 10)
            closedLidSection
            Divider().padding(.horizontal, 10)
            footer
        }
        .padding(.bottom, 6)
        .onAppear { loginController.refresh() }
    }

    // MARK: - Sections

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            disclosureRow("Duration", expanded: durationExpanded) {
                durationExpanded.toggle()
            }

            if durationExpanded {
                HStack(spacing: 5) {
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
                                .foregroundStyle(.secondary.opacity(0.55))
                                .padding(.horizontal, 1)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
    }

    private var closedLidSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Clamshell Mode")
                    .font(.system(size: 12))
                Spacer()
                Toggle("", isOn: $manager.closedLid)
                    .labelsHidden()
                    .toggleStyle(PillToggleStyle(width: 30, height: 18))
            }
            if let error = manager.clamshellError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .help("Stay awake with the lid closed. No external display required.")
    }

    private var footer: some View {
        VStack(spacing: 0) {
            settingsDisclosure

            MenuRow(title: "About") {
                if let url = URL(string: "https://github.com/AgarwalAarush/Caffeinated") {
                    openURL(url)
                }
            }
            MenuRow(title: "Quit") {
                NSApp.terminate(nil)
            }
        }
        .padding(.vertical, 2)
    }

    private var settingsDisclosure: some View {
        VStack(spacing: 0) {
            MenuRow(
                title: "Settings",
                trailing: .chevron,
                chevronRotation: settingsExpanded ? 90 : 0
            ) {}

            if settingsExpanded {
                settingsBody
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.18)) {
                settingsExpanded = hovering
            }
        }
    }

    private var settingsBody: some View {
        VStack(spacing: 0) {
            settingsRow("Open at Login", isOn: $loginController.isEnabled)
            settingsRow("Pause on Battery", isOn: $manager.pauseOnBattery)
            settingsRow("Allow Display Sleep", isOn: $manager.allowDisplaySleep)
            settingsRow("Notify When Timer Ends", isOn: $manager.notifyOnTimerEnd)
            settingsRow("Check Automatically", isOn: $updates.autoCheck)
            MenuRow(title: "Check for Updates...") {
                UpdatePrompt.shared.present()
            }
        }
        .padding(.bottom, 6)
    }

    private func disclosureRow(_ title: String, expanded: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                action()
            }
        } label: {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded ? 0 : -90))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
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
                    .fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.secondary.opacity(0.14)))
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
    var enabled: Bool = true
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
                        .foregroundStyle(hovering ? Color.white.opacity(0.9) : Color.secondary)
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
        .disabled(!enabled)
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
        .environmentObject(UpdateChecker.shared)
        .frame(width: 280)
}
