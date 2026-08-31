import AppKit
import Carbon

/// Global capture shortcuts that do not steal the system ⌘⇧3/4/5 combos.
/// Control-Shift-3 screen, Control-Shift-4 selection, Control-Shift-5 window.
@MainActor
final class CaptureHotKeys {
    static let shared = CaptureHotKeys()

    var onCapture: ((CaptureMode) -> Void)?

    private var installed = false
    private var hotKeyRefs: [EventHotKeyRef] = []

    func start() {
        guard !installed else { return }
        installed = true

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            caffeinatedHotKeyCallback,
            1,
            &spec,
            nil,
            nil
        )

        register(key: UInt32(kVK_ANSI_3), id: 1)
        register(key: UInt32(kVK_ANSI_4), id: 2)
        register(key: UInt32(kVK_ANSI_5), id: 3)
    }

    fileprivate func handle(id: UInt32) {
        switch id {
        case 1: onCapture?(.display)
        case 2: onCapture?(.area)
        case 3: onCapture?(.window)
        default: break
        }
    }

    private func register(key: UInt32, id: UInt32) {
        var ref: EventHotKeyRef?
        var hotKeyID = EventHotKeyID(signature: OSType(0x43616648), id: id) // 'CafH'
        let status = RegisterEventHotKey(
            key,
            UInt32(controlKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let ref {
            hotKeyRefs.append(ref)
        }
    }
}

private func caffeinatedHotKeyCallback(
    _: EventHandlerCallRef?,
    event: EventRef?,
    _: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return noErr }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    DispatchQueue.main.async {
        Task { @MainActor in
            CaptureHotKeys.shared.handle(id: hotKeyID.id)
        }
    }
    return noErr
}
