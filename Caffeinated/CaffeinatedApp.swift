import SwiftUI
import UserNotifications
import AppKit

@main
struct CaffeinatedApp: App {
    @StateObject private var manager = CaffeinateManager()
    @StateObject private var monitor = SystemMonitor()
    @StateObject private var capture = ScreenshotController()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            PopoverRoot(monitor: monitor, capture: capture)
                .environmentObject(manager)
                .environmentObject(UpdateChecker.shared)
                .onAppear {
                    CaptureHotKeys.shared.onCapture = { [capture] mode in
                        capture.begin(mode)
                    }
                    CaptureHotKeys.shared.start()
                }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: manager.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                if let countdown = manager.countdownLabel {
                    Text(countdown)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    UpdatePrompt.shared.present()
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        ClamshellSleep.restoreIfStale()
        UpdateChecker.shared.onUpdateFound = {
            UpdatePrompt.shared.present(recheck: false)
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            UpdateChecker.shared.checkIfDue()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if UserDefaults.standard.bool(forKey: ClamshellSleep.armedDefaultsKey) {
            ClamshellSleep.setDisabled(false)
            ClamshellSleep.markArmed(false)
        }
    }

    // Show banner + sound even when the app is in the foreground (which is
    // any time the menu-bar popover is open).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
