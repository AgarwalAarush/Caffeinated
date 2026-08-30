import Foundation
import AppKit
import IOKit.pwr_mgt
import Combine
import SwiftUI
import UserNotifications

enum CaffeinateDuration: Hashable, Identifiable {
    case indefinite
    case minutes(Int)
    case hours(Int)

    var id: String { label }

    var label: String {
        switch self {
        case .indefinite: return "∞"
        case .minutes(let m): return String(format: "%02d", m)
        case .hours(let h): return String(format: "%02d", h)
        }
    }

    var seconds: TimeInterval? {
        switch self {
        case .indefinite: return nil
        case .minutes(let m): return TimeInterval(m * 60)
        case .hours(let h): return TimeInterval(h * 3600)
        }
    }

    static let presets: [CaffeinateDuration] = [
        .indefinite,
        .minutes(15), .minutes(30), .minutes(45),
        .hours(1), .hours(4), .hours(8), .hours(12)
    ]
}

private enum PrefKey {
    static let pauseOnBattery = "pauseOnBattery"
    static let notifyOnTimerEnd = "notifyOnTimerEnd"
    static let allowDisplaySleep = "allowDisplaySleep"
    static let closedLid = "closedLid"
}

final class CaffeinateManager: ObservableObject {
    @Published private(set) var isActive: Bool = false
    @Published var selectedDuration: CaffeinateDuration = .indefinite
    @Published private(set) var remainingSeconds: TimeInterval?
    @Published private(set) var clamshellError: String?

    /// When true, an AC → battery transition will turn Caffeinated off.
    @Published var pauseOnBattery: Bool {
        didSet {
            guard pauseOnBattery != oldValue else { return }
            UserDefaults.standard.set(pauseOnBattery, forKey: PrefKey.pauseOnBattery)
        }
    }

    /// When true, fire a local notification when a timed session naturally
    /// expires. Enabling this asks the system for notification permission.
    @Published var notifyOnTimerEnd: Bool {
        didSet {
            guard notifyOnTimerEnd != oldValue else { return }
            UserDefaults.standard.set(notifyOnTimerEnd, forKey: PrefKey.notifyOnTimerEnd)
            if notifyOnTimerEnd {
                requestNotificationAuthorizationIfNeeded()
            }
        }
    }

    /// Keep the Mac awake but let the display dim / lock. Same primitive as
    /// `caffeinate -i` rather than `caffeinate -d`.
    @Published var allowDisplaySleep: Bool {
        didSet {
            guard allowDisplaySleep != oldValue else { return }
            UserDefaults.standard.set(allowDisplaySleep, forKey: PrefKey.allowDisplaySleep)
            if isActive {
                rebuildAssertion()
            }
        }
    }

    /// Keep running after the lid closes (no external display required).
    /// Arms a kernel clamshell-sleep disable bit for the duration of the
    /// session; restoring it is mandatory on stop/quit.
    @Published var closedLid: Bool {
        didSet {
            guard closedLid != oldValue else { return }
            UserDefaults.standard.set(closedLid, forKey: PrefKey.closedLid)
            if isActive {
                applyClamshellPolicy()
                rebuildAssertion()
            }
        }
    }

    var countdownLabel: String? {
        guard isActive, let remaining = remainingSeconds else { return nil }
        return Self.formatCountdown(remaining)
    }

    private let powerMonitor = PowerSourceMonitor()
    private var assertionID: IOPMAssertionID = IOPMAssertionID(0)
    private var timer: Timer?
    private var endDate: Date?
    private var clamshellArmed = false
    private var terminateObserver: NSObjectProtocol?

    init() {
        ClamshellSleep.restoreIfStale()

        self.pauseOnBattery = UserDefaults.standard.bool(forKey: PrefKey.pauseOnBattery)
        self.notifyOnTimerEnd = UserDefaults.standard.bool(forKey: PrefKey.notifyOnTimerEnd)
        self.allowDisplaySleep = UserDefaults.standard.bool(forKey: PrefKey.allowDisplaySleep)
        self.closedLid = UserDefaults.standard.bool(forKey: PrefKey.closedLid)

        powerMonitor.onTransitionToBattery = { [weak self] in
            guard let self else { return }
            if self.isActive && self.pauseOnBattery {
                self.stop()
            }
        }

        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stop()
        }
    }

    deinit {
        if let terminateObserver {
            NotificationCenter.default.removeObserver(terminateObserver)
        }
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
        }
        if clamshellArmed {
            ClamshellSleep.setDisabled(false)
            ClamshellSleep.markArmed(false)
        }
        timer?.invalidate()
    }

    func setActive(_ active: Bool) {
        if active {
            start()
        } else {
            stop()
        }
    }

    func toggle() {
        setActive(!isActive)
    }

    func selectDuration(_ duration: CaffeinateDuration) {
        selectedDuration = duration
        if isActive {
            scheduleTimer()
        } else {
            start()
        }
    }

    static func formatCountdown(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func start() {
        guard rebuildAssertion() else { return }
        applyClamshellPolicy()
        isActive = true
        scheduleTimer()
    }

    private func stop() {
        releaseAssertion()
        disarmClamshell()
        isActive = false
        timer?.invalidate()
        timer = nil
        endDate = nil
        remainingSeconds = nil
        clamshellError = nil
    }

    @discardableResult
    private func rebuildAssertion() -> Bool {
        releaseAssertion()
        let reason = "Caffeinated is keeping your Mac awake" as CFString
        var newID: IOPMAssertionID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            assertionType(),
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &newID
        )
        guard result == kIOReturnSuccess else { return false }
        assertionID = newID
        return true
    }

    private func releaseAssertion() {
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = IOPMAssertionID(0)
        }
    }

    private func assertionType() -> CFString {
        if closedLid {
            return kIOPMAssertionTypePreventSystemSleep as CFString
        }
        if allowDisplaySleep {
            return kIOPMAssertionTypePreventUserIdleSystemSleep as CFString
        }
        return kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString
    }

    private func applyClamshellPolicy() {
        if closedLid {
            ClamshellSleep.markArmed(true)
            let ok = ClamshellSleep.setDisabled(true)
            clamshellArmed = ok
            if !ok {
                ClamshellSleep.markArmed(false)
                clamshellError = "Couldn't disable lid-close sleep. The Mac may still sleep when you close it."
            } else {
                clamshellError = nil
            }
        } else {
            disarmClamshell()
        }
    }

    private func disarmClamshell() {
        guard clamshellArmed || UserDefaults.standard.bool(forKey: ClamshellSleep.armedDefaultsKey) else {
            return
        }
        ClamshellSleep.setDisabled(false)
        ClamshellSleep.markArmed(false)
        clamshellArmed = false
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = nil
        endDate = nil
        remainingSeconds = nil

        guard let seconds = selectedDuration.seconds else { return }

        let end = Date().addingTimeInterval(seconds)
        endDate = end
        remainingSeconds = seconds

        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard let end = endDate else { return }
        let remaining = end.timeIntervalSinceNow
        if remaining <= 0 {
            let shouldNotify = notifyOnTimerEnd
            stop()
            if shouldNotify {
                postTimerEndedNotification()
            }
        } else {
            remainingSeconds = remaining
        }
    }

    // MARK: - Notifications

    private func requestNotificationAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    private func postTimerEndedNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Caffeinated"
        content.body = "Timer ended — your Mac will sleep normally again."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "caffeinated.timer-ended.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
