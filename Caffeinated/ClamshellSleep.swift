import Foundation
import IOKit
import Darwin

/// Disables or restores lid-close (clamshell) sleep via IOPMrootDomain.
///
/// `caffeinate` and a normal idle-sleep assertion do **not** keep an Apple
/// Silicon Mac awake when the lid closes. The kernel only skips that
/// transition when the clamshell-sleep disable bit is set — the same bit
/// `pmset -a disablesleep 1` flips, reachable from user space through
/// `kPMSetClamshellSleepState` (selector 12) without root.
///
/// The flag is process-independent and sticky: if we arm it and then
/// crash, it stays set until something clears it. Callers must restore
/// it on stop, on quit, and on the next launch if a previous session
/// died while armed.
enum ClamshellSleep {
    /// `kPMSetClamshellSleepState` in `RootDomainUserClient`.
    private static let setClamshellSleepState: UInt32 = 12

    /// UserDefaults key recording that *this* app currently owns the flag.
    static let armedDefaultsKey = "clamshellSleepArmedByCaffeinated"

    @discardableResult
    static func setDisabled(_ disabled: Bool) -> Bool {
        let matching = IOServiceMatching("IOPMrootDomain")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }

        var connect: io_connect_t = 0
        let open = IOServiceOpen(service, mach_task_self_, 0, &connect)
        guard open == KERN_SUCCESS, connect != 0 else { return false }
        defer { IOServiceClose(connect) }

        var input: UInt64 = disabled ? 1 : 0
        let result = IOConnectCallScalarMethod(
            connect,
            setClamshellSleepState,
            &input,
            1,
            nil,
            nil
        )
        return result == KERN_SUCCESS
    }

    /// If a previous run died while closed-lid mode was on, put sleep back
    /// to normal so the Mac cannot get stuck awake.
    static func restoreIfStale() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: armedDefaultsKey) else { return }
        setDisabled(false)
        defaults.set(false, forKey: armedDefaultsKey)
    }

    static func markArmed(_ armed: Bool) {
        UserDefaults.standard.set(armed, forKey: armedDefaultsKey)
    }
}
