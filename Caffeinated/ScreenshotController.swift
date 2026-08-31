import AppKit
import Combine
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

enum CaptureMode: String, CaseIterable, Identifiable {
    case area, window, display

    var id: String { rawValue }

    var title: String {
        switch self {
        case .area: return "Selection"
        case .window: return "Window"
        case .display: return "Screen"
        }
    }

    var symbol: String {
        switch self {
        case .area: return "rectangle.dashed"
        case .window: return "macwindow"
        case .display: return "display"
        }
    }

    var help: String {
        switch self {
        case .area: return "Drag a region. Esc cancels, Return confirms."
        case .window: return "Click a window. Esc cancels."
        case .display: return "Click a display. Esc cancels."
        }
    }
}

/// Frozen-screen overlay: capture first, then let the user crop a region,
/// window, or whole display from the still picture so Caffeinated's own UI
/// never appears in the shot.
final class ScreenshotController: ObservableObject {
    @Published var lastImage: NSImage?
    @Published var permissionDenied = false
    @Published var copyOnCapture: Bool {
        didSet { UserDefaults.standard.set(copyOnCapture, forKey: "copyOnCapture") }
    }
    @Published var isCapturing = false
    @Published var statusMessage: String?

    private var session: CaptureOverlaySession?
    private var preview: CaptureEditorPanel?

    init() {
        self.copyOnCapture = UserDefaults.standard.object(forKey: "copyOnCapture") as? Bool ?? true
    }

    func requestPermission() async {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            permissionDenied = false
        } catch {
            permissionDenied = true
        }
    }

    func begin(_ mode: CaptureMode) {
        guard !isCapturing else { return }
        isCapturing = true
        statusMessage = nil
        PopoverDismiss.resign()
        NSApp.activate(ignoringOtherApps: true)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            PopoverDismiss.resign()
            do {
                let frozen = try await Self.freezeDisplays()
                guard !frozen.isEmpty else {
                    permissionDenied = true
                    isCapturing = false
                    statusMessage = "Screen Recording permission is required."
                    return
                }
                permissionDenied = false
                let session = CaptureOverlaySession(mode: mode, displays: frozen) { [weak self] image in
                    self?.finish(with: image)
                } onCancel: { [weak self] in
                    self?.isCapturing = false
                    self?.statusMessage = "Cancelled"
                }
                self.session = session
                session.present()
            } catch {
                permissionDenied = true
                isCapturing = false
                statusMessage = "Screen Recording permission is required."
            }
        }
    }

    private func finish(with image: NSImage?) {
        session = nil
        isCapturing = false
        guard let image else { return }
        lastImage = image
        if copyOnCapture {
            copyToClipboard(image)
            statusMessage = "Copied to clipboard"
        }
        showEditor(image)
    }

    func copyLast() {
        guard let lastImage else { return }
        copyToClipboard(lastImage)
        statusMessage = "Copied to clipboard"
    }

    func saveLast() {
        guard let lastImage else { return }
        save(lastImage)
    }

    private func copyToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        if let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            pasteboard.setData(png, forType: .png)
        }
    }

    private func save(_ image: NSImage) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = Self.defaultFilename()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return }
            try? png.write(to: url)
        }
    }

    func editLast() {
        guard let lastImage else { return }
        showEditor(lastImage)
    }

    func copyEdited(_ image: NSImage) {
        lastImage = image
        copyToClipboard(image)
        statusMessage = "Copied to clipboard"
    }

    func saveEdited(_ image: NSImage) {
        lastImage = image
        save(image)
    }

    private func showEditor(_ image: NSImage) {
        if let existing = preview {
            existing.orderOut(nil)
        }
        preview = nil
        let panel = CaptureEditorPanel(
            image: image,
            onCopy: { [weak self] output in
                self?.copyEdited(output)
            },
            onSave: { [weak self] output in
                self?.saveEdited(output)
            },
            onClose: { [weak self] output in
                if let output { self?.lastImage = output }
                self?.preview = nil
            }
        )
        preview = panel
        panel.show()
    }

    private static func defaultFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screen Shot \(formatter.string(from: Date())).png"
    }

    private static func freezeDisplays() async throws -> [FrozenDisplay] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var frozen: [FrozenDisplay] = []
        for display in content.displays {
            guard let screen = NSScreen.screens.first(where: { $0.displayID == display.displayID }) else {
                continue
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.showsCursor = false
            config.capturesAudio = false
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            let windows = content.windows.compactMap { window -> FrozenWindow? in
                guard window.isOnScreen, window.frame.width >= 40, window.frame.height >= 40 else {
                    return nil
                }
                let appKitFrame = cgRectToAppKit(window.frame)
                guard appKitFrame.intersects(screen.frame.insetBy(dx: -2, dy: -2)) else { return nil }
                return FrozenWindow(
                    frame: appKitFrame,
                    title: window.title ?? window.owningApplication?.applicationName ?? "Window"
                )
            }
            frozen.append(FrozenDisplay(screen: screen, image: image, windows: windows))
        }
        return frozen
    }
}

struct FrozenDisplay {
    let screen: NSScreen
    let image: CGImage
    let windows: [FrozenWindow]
}

struct FrozenWindow {
    let frame: CGRect
    let title: String
}

enum PopoverDismiss {
    static func resign() {
        for window in NSApp.windows where window.isVisible {
            let name = window.className
            if name.contains("MenuBarExtra")
                || name.contains("StatusItem")
                || (window.isFloatingPanel && window.frame.width < 420 && window.level != .screenSaver) {
                window.orderOut(nil)
            }
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? CGDirectDisplayID) ?? 0
    }
}

/// Convert a CoreGraphics top-left rect (global, main-display origin) to AppKit
/// bottom-left coordinates.
func cgRectToAppKit(_ rect: CGRect) -> CGRect {
    guard let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.main else {
        return rect
    }
    return CGRect(
        x: rect.origin.x,
        y: primary.frame.height - rect.origin.y - rect.height,
        width: rect.width,
        height: rect.height
    )
}

// MARK: - Overlay session

final class CaptureOverlaySession {
    private let mode: CaptureMode
    private let displays: [FrozenDisplay]
    private var windows: [CaptureOverlayWindow] = []
    private let onComplete: (NSImage?) -> Void
    private let onCancel: () -> Void
    private var finished = false
    private var keyMonitor: Any?
    private var mouseMonitor: Any?

    init(
        mode: CaptureMode,
        displays: [FrozenDisplay],
        onComplete: @escaping (NSImage?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.displays = displays
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    func present() {
        if mode == .display, displays.count == 1, let only = displays.first {
            complete(crop: only.screen.frame, in: only)
            return
        }

        for frozen in displays {
            let window = CaptureOverlayWindow(frozen: frozen, mode: mode)
            window.onDragSelect = { [weak self] rect in
                self?.complete(crop: rect, in: frozen)
            }
            window.onWindowSelect = { [weak self] frame in
                self?.complete(crop: frame, in: frozen)
            }
            window.onDisplaySelect = { [weak self] in
                self?.complete(crop: frozen.screen.frame, in: frozen)
            }
            window.onCancel = { [weak self] in
                self?.cancel()
            }
            windows.append(window)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(window.contentView)
        }
        windows.first?.makeKey()
        windows.first?.makeFirstResponder(windows.first?.contentView)

        let handleKey: (NSEvent) -> NSEvent? = { [weak self] event in
            if event.keyCode == 53 { // escape
                self?.cancel()
                return nil
            }
            if event.keyCode == 36 || event.keyCode == 76 { // return / keypad enter
                self?.windows.forEach { $0.confirmSelection() }
                return nil
            }
            return event
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handleKey)
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            _ = handleKey(event)
        }
    }

    private func complete(crop screenRect: CGRect, in frozen: FrozenDisplay) {
        guard !finished else { return }
        finished = true
        tearDown()
        let image = crop(frozen.image, to: screenRect, screen: frozen.screen)
        onComplete(image)
    }

    private func cancel() {
        guard !finished else { return }
        finished = true
        tearDown()
        onCancel()
        onComplete(nil)
    }

    private func tearDown() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private func crop(_ image: CGImage, to screenRect: CGRect, screen: NSScreen) -> NSImage? {
        let frame = screen.frame
        let scaleX = CGFloat(image.width) / frame.width
        let scaleY = CGFloat(image.height) / frame.height
        let localX = screenRect.origin.x - frame.origin.x
        let localYFromBottom = screenRect.origin.y - frame.origin.y
        let localYFromTop = frame.height - localYFromBottom - screenRect.height
        let pixel = CGRect(
            x: localX * scaleX,
            y: localYFromTop * scaleY,
            width: screenRect.width * scaleX,
            height: screenRect.height * scaleY
        ).integral
        guard pixel.width >= 2, pixel.height >= 2,
              let cropped = image.cropping(to: pixel) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: screenRect.width, height: screenRect.height))
    }
}

final class CaptureOverlayWindow: NSPanel {
    var onDragSelect: ((CGRect) -> Void)?
    var onWindowSelect: ((CGRect) -> Void)?
    var onDisplaySelect: (() -> Void)?
    var onCancel: (() -> Void)?

    private let freezeView: FreezeOverlayView

    init(frozen: FrozenDisplay, mode: CaptureMode) {
        freezeView = FreezeOverlayView(frozen: frozen, mode: mode)
        super.init(
            contentRect: frozen.screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        setFrame(frozen.screen.frame, display: true)
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isFloatingPanel = true
        hidesOnDeactivate = false
        animationBehavior = .none
        ignoresMouseEvents = false
        hasShadow = false
        contentView = freezeView
        freezeView.onDragSelect = { [weak self] rect in
            self?.onDragSelect?(rect)
        }
        freezeView.onWindowSelect = { [weak self] rect in
            self?.onWindowSelect?(rect)
        }
        freezeView.onDisplaySelect = { [weak self] in
            self?.onDisplaySelect?()
        }
        freezeView.onCancel = { [weak self] in
            self?.onCancel?()
        }
    }

    func confirmSelection() {
        freezeView.confirm()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class FreezeOverlayView: NSView {
    var onDragSelect: ((CGRect) -> Void)?
    var onWindowSelect: ((CGRect) -> Void)?
    var onDisplaySelect: (() -> Void)?
    var onCancel: (() -> Void)?

    private let frozen: FrozenDisplay
    private let mode: CaptureMode
    private let nsImage: NSImage
    private var dragStart: NSPoint?
    private var dragCurrent: NSPoint?
    private var hoverWindow: FrozenWindow?

    init(frozen: FrozenDisplay, mode: CaptureMode) {
        self.frozen = frozen
        self.mode = mode
        self.nsImage = NSImage(cgImage: frozen.image, size: frozen.screen.frame.size)
        super.init(frame: NSRect(origin: .zero, size: frozen.screen.frame.size))
        wantsLayer = true
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseMoved, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        ))
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        nsImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)

        NSColor.black.withAlphaComponent(0.45).setFill()
        bounds.fill()

        switch mode {
        case .area:
            if let selection = currentSelection(), selection.width > 2, selection.height > 2 {
                let local = toLocal(selection)
                nsImage.draw(in: local, from: local, operation: .copy, fraction: 1)
                NSColor.controlAccentColor.setStroke()
                let path = NSBezierPath(rect: local.insetBy(dx: 0.5, dy: 0.5))
                path.lineWidth = 2
                path.stroke()
                drawSizeLabel(for: selection, localRect: local)
            }
            drawHint("Drag a region · Esc cancels · Return captures")
        case .window:
            if let hover = hoverWindow {
                let local = toLocal(hover.frame)
                nsImage.draw(in: local, from: local, operation: .copy, fraction: 1)
                NSColor.controlAccentColor.setStroke()
                let path = NSBezierPath(rect: local.insetBy(dx: 0.5, dy: 0.5))
                path.lineWidth = 3
                path.stroke()
                drawTitle(hover.title, in: local)
            }
            drawHint("Click a window · Esc cancels")
        case .display:
            NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
            bounds.fill()
            drawTitle("Click to capture this display", in: bounds)
            drawHint("Esc cancels")
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        if event.keyCode == 36 || event.keyCode == 76 {
            confirm()
            return
        }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch mode {
        case .area:
            dragStart = point
            dragCurrent = point
            needsDisplay = true
        case .window:
            if let hover = window(at: point) {
                onWindowSelect?(hover.frame)
            }
        case .display:
            onDisplaySelect?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard mode == .area else { return }
        dragCurrent = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard mode == .area else { return }
        dragCurrent = convert(event.locationInWindow, from: nil)
        if let selection = currentSelection(), selection.width > 4, selection.height > 4 {
            onDragSelect?(selection)
        } else {
            dragStart = nil
            dragCurrent = nil
            needsDisplay = true
        }
    }

    override func mouseMoved(with event: NSEvent) {
        guard mode == .window else { return }
        let point = convert(event.locationInWindow, from: nil)
        let next = window(at: point)
        if next?.frame != hoverWindow?.frame {
            hoverWindow = next
            needsDisplay = true
        }
    }

    func confirm() {
        if mode == .area, let selection = currentSelection(), selection.width > 4, selection.height > 4 {
            onDragSelect?(selection)
        }
    }

    private func currentSelection() -> CGRect? {
        guard let start = dragStart, let current = dragCurrent else { return nil }
        let local = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        return NSRect(
            x: local.origin.x + frozen.screen.frame.origin.x,
            y: local.origin.y + frozen.screen.frame.origin.y,
            width: local.width,
            height: local.height
        )
    }

    private func toLocal(_ screenRect: CGRect) -> NSRect {
        NSRect(
            x: screenRect.origin.x - frozen.screen.frame.origin.x,
            y: screenRect.origin.y - frozen.screen.frame.origin.y,
            width: screenRect.width,
            height: screenRect.height
        )
    }

    private func window(at localPoint: NSPoint) -> FrozenWindow? {
        let screenPoint = NSPoint(
            x: localPoint.x + frozen.screen.frame.origin.x,
            y: localPoint.y + frozen.screen.frame.origin.y
        )
        // SCShareableContent.windows is front-to-back.
        return frozen.windows.first(where: { $0.frame.contains(screenPoint) })
    }

    private func drawSizeLabel(for selection: CGRect, localRect: NSRect) {
        let text = "\(Int(selection.width)) × \(Int(selection.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attrs)
        var origin = NSPoint(x: localRect.minX, y: localRect.minY - size.height - 8)
        if origin.y < 4 { origin.y = localRect.minY + 6 }
        let bg = NSRect(x: origin.x, y: origin.y - 2, width: size.width + 10, height: size.height + 4)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 4, yRadius: 4).fill()
        text.draw(at: NSPoint(x: origin.x + 5, y: origin.y), withAttributes: attrs)
    }

    private func drawHint(_ title: String) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = title.size(withAttributes: attrs)
        let origin = NSPoint(x: bounds.midX - size.width / 2, y: 18)
        let bg = NSRect(x: origin.x - 10, y: origin.y - 6, width: size.width + 20, height: size.height + 12)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 8, yRadius: 8).fill()
        title.draw(at: origin, withAttributes: attrs)
    }

    private func drawTitle(_ title: String, in rect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = title.size(withAttributes: attrs)
        let origin = NSPoint(
            x: rect.midX - size.width / 2,
            y: min(rect.maxY - size.height - 10, rect.midY)
        )
        let bg = NSRect(x: origin.x - 8, y: origin.y - 4, width: size.width + 16, height: size.height + 8)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 6, yRadius: 6).fill()
        title.draw(at: origin, withAttributes: attrs)
    }
}
