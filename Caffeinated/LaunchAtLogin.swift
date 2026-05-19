import Foundation
import Combine
import ServiceManagement

final class LaunchAtLoginController: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            apply(isEnabled)
        }
    }

    init() {
        self.isEnabled = (SMAppService.mainApp.status == .enabled)
    }

    /// Re-reads the system state — call when the popover reappears in case the
    /// user toggled the setting from System Settings → General → Login Items.
    func refresh() {
        let actual = (SMAppService.mainApp.status == .enabled)
        if actual != isEnabled {
            // Sync without re-triggering apply()
            DispatchQueue.main.async {
                if self.isEnabled != actual {
                    // didSet will be a no-op because new == old after this assignment,
                    // so update via Published projected value instead.
                    self.isEnabled = actual
                }
            }
        }
    }

    private func apply(_ enabled: Bool) {
        do {
            let service = SMAppService.mainApp
            switch (enabled, service.status) {
            case (true, .enabled):
                return
            case (true, _):
                try service.register()
            case (false, .enabled):
                try service.unregister()
            case (false, _):
                return
            }
        } catch {
            // The most common failure mode is an unsigned / not-yet-installed-to-Applications
            // debug build. Snap the toggle back to whatever the system actually thinks.
            let actual = (SMAppService.mainApp.status == .enabled)
            DispatchQueue.main.async {
                if self.isEnabled != actual {
                    self.isEnabled = actual
                }
            }
        }
    }
}
