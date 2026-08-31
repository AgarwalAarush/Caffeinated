import AppKit
import SwiftUI

/// Sparkle-style software-update panel. Caffeinated is an accessory app, so
/// this is a floating window rather than a page inside the menu-bar popover.
@MainActor
final class UpdatePrompt: NSObject {
    static let shared = UpdatePrompt()

    private var panel: NSPanel?
    private var keyMonitor: Any?

    func present(recheck: Bool = true) {
        PopoverDismiss.resign()
        NSApp.activate(ignoringOtherApps: true)
        if panel == nil { build() }
        installKeyMonitor()
        panel?.center()
        panel?.makeKeyAndOrderFront(nil)
        if recheck {
            Task { await UpdateChecker.shared.check(interactive: true) }
        }
    }

    func dismiss() {
        panel?.orderOut(nil)
    }

    private func build() {
        let root = UpdatePromptView { [weak self] in
            self?.dismiss()
        }
        .environmentObject(UpdateChecker.shared)

        let hosting = NSHostingView(rootView: root)
        let size = NSSize(width: 320, height: 280)
        hosting.frame = NSRect(origin: .zero, size: size)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Software Update"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentView = hosting
        self.panel = panel
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        let panel = self.panel
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak panel] event in
            guard event.keyCode == 53, panel?.isKeyWindow == true else { return event }
            Task { @MainActor in UpdatePrompt.shared.dismiss() }
            return nil
        }
    }
}

struct UpdatePromptView: View {
    @EnvironmentObject private var updates: UpdateChecker
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 64, height: 64)
                .padding(.top, 8)

            Text(headline)
                .font(.system(size: 15, weight: .semibold))
                .multilineTextAlignment(.center)

            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)

            if showSpinner {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 2)
            }

            VStack(spacing: 8) {
                if updates.phase == .available {
                    Button {
                        Task { await updates.install() }
                    } label: {
                        Text(installTitle)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(UpdatePrimaryButtonStyle())
                    .disabled(updates.isBusy)

                    Button("Later") { onClose() }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .disabled(updates.isBusy)
                } else if updates.phase == .checking || updates.phase == .downloading || updates.phase == .installing {
                    Color.clear.frame(height: 12)
                } else {
                    Button("OK") { onClose() }
                        .buttonStyle(UpdatePrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 22)
        .padding(.top, 18)
        .frame(width: 320)
        .onExitCommand { onClose() }
    }

    private var showSpinner: Bool {
        switch updates.phase {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    private var headline: String {
        switch updates.phase {
        case .checking: return "Checking for updates…"
        case .downloading: return "Downloading…"
        case .installing: return "Installing…"
        case .available: return "Version \(updates.availableVersion ?? "") is available"
        case .failed: return "Couldn’t check for updates"
        case .current, .idle: return "You’re up to date!"
        }
    }

    private var detail: String {
        switch updates.phase {
        case .checking:
            return "Looking for a newer GitHub Release."
        case .downloading, .installing:
            return updates.status
        case .available:
            return "Caffeinated \(updates.currentVersion) is currently installed."
        case .failed:
            return updates.status.isEmpty ? "Try again in a moment." : updates.status
        case .current, .idle:
            return "Caffeinated \(updates.currentVersion) is currently the newest version available."
        }
    }

    private var installTitle: String {
        if let version = updates.availableVersion { return "Install \(version)" }
        return "Install"
    }
}

private struct UpdatePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.82 : 1))
            )
    }
}
