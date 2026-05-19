import Foundation
import Combine
import IOKit
import IOKit.ps

/// Watches the system's power source. Publishes `isOnBattery` and invokes
/// `onTransitionToBattery` whenever the Mac switches from AC power to battery
/// (the trigger we care about for "pause caffeinated when unplugged").
final class PowerSourceMonitor: ObservableObject {
    @Published private(set) var isOnBattery: Bool = false

    var onTransitionToBattery: (() -> Void)?

    private var runLoopSource: CFRunLoopSource?

    init() {
        self.isOnBattery = Self.readIsOnBattery()
        installNotification()
    }

    deinit {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    // MARK: - Private

    private func installNotification() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { ctx in
            guard let ctx = ctx else { return }
            let monitor = Unmanaged<PowerSourceMonitor>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async {
                monitor.refresh()
            }
        }
        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else {
            return
        }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    private func refresh() {
        let wasOnBattery = isOnBattery
        let now = Self.readIsOnBattery()
        guard now != wasOnBattery else { return }
        isOnBattery = now
        if !wasOnBattery && now {
            onTransitionToBattery?()
        }
    }

    private static func readIsOnBattery() -> Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return false
        }
        let type = IOPSGetProvidingPowerSourceType(blob).takeUnretainedValue() as String
        // kIOPSBatteryPowerValue == "Battery Power"
        return type == (kIOPSBatteryPowerValue as String)
    }
}
