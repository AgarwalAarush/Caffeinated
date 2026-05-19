import Foundation
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
}

final class CaffeinateManager: ObservableObject {
    @Published private(set) var isActive: Bool = false
    @Published var selectedDuration: CaffeinateDuration = .indefinite
    @Published private(set) var remainingSeconds: TimeInterval?

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

    private let powerMonitor = PowerSourceMonitor()
    private var assertionID: IOPMAssertionID = IOPMAssertionID(0)
    private var timer: Timer?
    private var endDate: Date?

    init() {
        self.pauseOnBattery = UserDefaults.standard.bool(forKey: PrefKey.pauseOnBattery)
        self.notifyOnTimerEnd = UserDefaults.standard.bool(forKey: PrefKey.notifyOnTimerEnd)

        powerMonitor.onTransitionToBattery = { [weak self] in
            guard let self else { return }
            if self.isActive && self.pauseOnBattery {
                self.stop()
            }
        }
    }

    deinit {
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
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

    private func start() {
        if assertionID == 0 {
            let reason = "Caffeinated is keeping your Mac awake" as CFString
            var newID: IOPMAssertionID = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &newID
            )
            guard result == kIOReturnSuccess else { return }
            assertionID = newID
        }
        isActive = true
        scheduleTimer()
    }

    private func stop() {
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = IOPMAssertionID(0)
        }
        isActive = false
        timer?.invalidate()
        timer = nil
        endDate = nil
        remainingSeconds = nil
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
