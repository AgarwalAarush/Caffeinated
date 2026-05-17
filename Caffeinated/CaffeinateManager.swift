import Foundation
import IOKit.pwr_mgt
import Combine
import SwiftUI

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

final class CaffeinateManager: ObservableObject {
    @Published private(set) var isActive: Bool = false
    @Published var selectedDuration: CaffeinateDuration = .indefinite
    @Published private(set) var remainingSeconds: TimeInterval?

    private var assertionID: IOPMAssertionID = IOPMAssertionID(0)
    private var timer: Timer?
    private var endDate: Date?

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
            stop()
        } else {
            remainingSeconds = remaining
        }
    }
}
