import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

enum MarkupTool: String, CaseIterable, Identifiable {
    case pen, arrow, rectangle, ellipse, highlight, blur, text, crop

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .pen: return "pencil.tip"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "oval"
        case .highlight: return "highlighter"
        case .blur: return "eye.slash"
        case .text: return "textformat"
        case .crop: return "crop"
        }
    }

    var help: String {
        switch self {
        case .pen: return "Draw"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .highlight: return "Highlight"
        case .blur: return "Redact"
        case .text: return "Text"
        case .crop: return "Crop"
        }
    }
}

struct MarkupItem: Identifiable {
    let id: UUID
    var kind: Kind
    var color: Color
    var lineWidth: CGFloat

    enum Kind {
        case pen([CGPoint])
        case arrow(CGPoint, CGPoint)
        case rect(CGRect)
        case ellipse(CGRect)
        case highlight(CGRect)
        case blur(CGRect)
        case text(CGPoint, String)
    }

    init(kind: Kind, color: Color, lineWidth: CGFloat) {
        self.id = UUID()
        self.kind = kind
        self.color = color
        self.lineWidth = lineWidth
    }
}

@MainActor
final class CaptureEditorSession: ObservableObject {
    @Published var image: NSImage
    @Published var items: [MarkupItem] = []
    @Published var tool: MarkupTool = .arrow
    @Published var color: Color = Color(red: 1, green: 0.27, blue: 0.23)
    @Published var draft: MarkupItem?
    @Published var textOrigin: CGPoint?
    @Published var textDraft: String = ""

    static let swatches: [Color] = [
        .white,
        .black,
        Color(red: 1, green: 0.27, blue: 0.23),
        Color(red: 1, green: 0.62, blue: 0.04),
        Color(red: 1, green: 0.84, blue: 0.04),
        Color(red: 0.20, green: 0.84, blue: 0.29),
        Color(red: 0.04, green: 0.52, blue: 1.0)
    ]

    init(image: NSImage) {
        self.image = image
    }

    var canUndo: Bool { !items.isEmpty || draft != nil || textOrigin != nil }

    func undo() {
        if textOrigin != nil {
            textOrigin = nil
            textDraft = ""
            return
        }
        if draft != nil {
            draft = nil
            return
        }
        if !items.isEmpty {
            items.removeLast()
        }
    }

    func commitDraft() {
        guard let draft else { return }
        if case .pen(let points) = draft.kind, points.count < 2 {
            self.draft = nil
            return
        }
        items.append(draft)
        self.draft = nil
    }

    func commitText() {
        let trimmed = textDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if let origin = textOrigin, !trimmed.isEmpty {
            items.append(MarkupItem(kind: .text(origin, trimmed), color: color, lineWidth: 14))
        }
        textOrigin = nil
        textDraft = ""
    }

    func applyCrop(_ rect: CGRect) {
        guard rect.width > 8, rect.height > 8 else {
            draft = nil
            return
        }
        let baked = flattened()
        guard let cg = baked.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let scaleX = CGFloat(cg.width) / max(baked.size.width, 1)
        let scaleY = CGFloat(cg.height) / max(baked.size.height, 1)
        let pixel = CGRect(
            x: rect.minX * scaleX,
            y: rect.minY * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        ).integral
        guard let cropped = cg.cropping(to: pixel) else { return }
        image = NSImage(cgImage: cropped, size: NSSize(width: rect.width, height: rect.height))
        items = []
        draft = nil
    }

    func flattened() -> NSImage {
        MarkupRenderer.flatten(image: image, items: items)
    }
}

enum MarkupRenderer {
    static func flatten(image: NSImage, items: [MarkupItem]) -> NSImage {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }
        let width = source.width
        let height = source.height
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        ctx.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        let scaleX = CGFloat(width) / max(image.size.width, 1)
        let scaleY = CGFloat(height) / max(image.size.height, 1)
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: scaleX, y: -scaleY)

        for item in items {
            draw(item, in: ctx)
        }

        guard let out = ctx.makeImage() else { return image }
        return NSImage(cgImage: out, size: image.size)
    }

    static func draw(_ item: MarkupItem, in ctx: CGContext) {
        let nsColor = NSColor(item.color)
        ctx.setStrokeColor(nsColor.cgColor)
        ctx.setFillColor(nsColor.cgColor)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(item.lineWidth)

        switch item.kind {
        case .pen(let points):
            guard let first = points.first else { return }
            ctx.beginPath()
            ctx.move(to: first)
            for point in points.dropFirst() { ctx.addLine(to: point) }
            ctx.strokePath()
        case .arrow(let from, let to):
            ctx.beginPath()
            ctx.move(to: from)
            ctx.addLine(to: to)
            ctx.strokePath()
            addArrowHead(from: from, to: to, width: item.lineWidth, in: ctx)
        case .rect(let rect):
            ctx.addRect(rect)
            ctx.strokePath()
        case .ellipse(let rect):
            ctx.strokeEllipse(in: rect)
        case .highlight(let rect):
            ctx.setFillColor(nsColor.withAlphaComponent(0.38).cgColor)
            ctx.fill(rect)
        case .blur(let rect):
            pixelate(rect, in: ctx)
        case .text(let origin, let string):
            drawText(string, at: origin, color: nsColor, size: max(16, item.lineWidth + 4))
        }
    }

    private static func addArrowHead(from: CGPoint, to: CGPoint, width: CGFloat, in ctx: CGContext) {
        let angle = atan2(to.y - from.y, to.x - from.x)
        let length = max(12, width * 4)
        let spread: CGFloat = .pi / 7
        ctx.beginPath()
        ctx.move(to: to)
        ctx.addLine(to: CGPoint(x: to.x - length * cos(angle - spread), y: to.y - length * sin(angle - spread)))
        ctx.move(to: to)
        ctx.addLine(to: CGPoint(x: to.x - length * cos(angle + spread), y: to.y - length * sin(angle + spread)))
        ctx.strokePath()
    }

    private static func pixelate(_ rect: CGRect, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
        ctx.fill(rect)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.18).cgColor)
        let step: CGFloat = 8
        var y = rect.minY
        var row = 0
        while y < rect.maxY {
            var x = rect.minX
            var col = 0
            while x < rect.maxX {
                if (row + col) % 2 == 0 {
                    ctx.fill(CGRect(x: x, y: y, width: min(step, rect.maxX - x), height: min(step, rect.maxY - y)))
                }
                x += step
                col += 1
            }
            y += step
            row += 1
        }
        ctx.restoreGState()
    }

    private static func drawText(_ string: String, at origin: CGPoint, color: NSColor, size: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: color,
            .strokeColor: NSColor.black.withAlphaComponent(0.55),
            .strokeWidth: -2
        ]
        (string as NSString).draw(at: origin, withAttributes: attrs)
    }
}

// MARK: - Panel

final class CaptureEditorPanel: NSPanel {
    private var onClose: (NSImage?) -> Void
    private let onCopyImage: (NSImage) -> Void
    private let onSaveImage: (NSImage) -> Void
    private let session: CaptureEditorSession
    private var keyMonitor: Any?

    init(
        image: NSImage,
        onCopy: @escaping (NSImage) -> Void,
        onSave: @escaping (NSImage) -> Void,
        onClose: @escaping (NSImage?) -> Void
    ) {
        self.onClose = onClose
        self.onCopyImage = onCopy
        self.onSaveImage = onSave
        self.session = CaptureEditorSession(image: image)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let width = min(max(image.size.width + 48, 560), min(1080, screen.width * 0.86))
        let height = min(max(image.size.height + 108, 420), min(760, screen.height * 0.86))

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = "Edit Capture"
        titlebarAppearsTransparent = true
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        minSize = NSSize(width: 480, height: 360)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true

        let session = self.session
        let copy = onCopy
        let save = onSave
        let root = CaptureEditorView(
            session: session,
            onCopy: { copy(session.flattened()) },
            onSave: { save(session.flattened()) },
            onDone: { [weak self] in self?.close() }
        )
        contentView = NSHostingView(rootView: root)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        center()
        makeKeyAndOrderFront(nil)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.session.textOrigin != nil { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 53 {
                self.close()
                return nil
            }
            if mods.contains(.command) {
                switch event.charactersIgnoringModifiers {
                case "z":
                    self.session.undo()
                    return nil
                case "c":
                    self.session.commitText()
                    self.onCopyImage(self.session.flattened())
                    return nil
                case "s":
                    self.session.commitText()
                    self.onSaveImage(self.session.flattened())
                    return nil
                default:
                    break
                }
            }
            return event
        }
    }

    private var didClose = false

    override func close() {
        guard !didClose else { return }
        didClose = true
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        onClose(session.flattened())
        super.close()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Editor UI

struct CaptureEditorView: View {
    @ObservedObject var session: CaptureEditorSession
    var onCopy: () -> Void
    var onSave: () -> Void
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.top, 36)
                .padding(.horizontal, 16)
            canvas
                .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.22))
        .focusable()
        .onKeyPress { press in
            if press.key == .escape {
                if session.textOrigin != nil || session.draft != nil {
                    session.draft = nil
                    session.textOrigin = nil
                    session.textDraft = ""
                    return .handled
                }
                onDone()
                return .handled
            }
            if press.modifiers.contains(.command) {
                switch press.characters {
                case "z":
                    session.undo()
                    return .handled
                case "c":
                    session.commitText()
                    onCopy()
                    return .handled
                case "s":
                    session.commitText()
                    onSave()
                    return .handled
                default:
                    break
                }
            }
            return .ignored
        }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            ForEach(MarkupTool.allCases) { tool in
                toolButton(tool)
            }
            toolbarDivider
            Button(action: session.undo) {
                Image(systemName: "arrow.uturn.backward")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(!session.canUndo)
            .help("Undo (⌘Z)")
            toolbarDivider
            HStack(spacing: 6) {
                ForEach(Array(CaptureEditorSession.swatches.enumerated()), id: \.offset) { _, swatch in
                    Button {
                        session.color = swatch
                    } label: {
                        Circle()
                            .fill(swatch)
                            .frame(width: 14, height: 14)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.9), lineWidth: colorsEqual(session.color, swatch) ? 2 : 0)
                            )
                            .overlay(
                                Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 12)
            actionButton("Copy", symbol: "doc.on.doc") {
                session.commitText()
                onCopy()
            }
            actionButton("Save", symbol: "square.and.arrow.down") {
                session.commitText()
                onSave()
            }
            actionButton("Done", symbol: "checkmark") {
                session.commitText()
                onDone()
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.18))
            .frame(width: 1, height: 16)
            .padding(.horizontal, 4)
    }

    private func toolButton(_ tool: MarkupTool) -> some View {
        Button {
            session.commitText()
            session.tool = tool
        } label: {
            Image(systemName: tool.symbol)
                .frame(width: 28, height: 28)
                .background(
                    Capsule()
                        .fill(session.tool == tool ? Color.accentColor : Color.clear)
                )
                .foregroundStyle(session.tool == tool ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .help(tool.help)
    }

    private func actionButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                Text(title)
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.accentColor.opacity(title == "Done" ? 1 : 0.16)))
            .foregroundStyle(title == "Done" ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private var canvas: some View {
        GeometryReader { geo in
            let fit = FittedImage(imageSize: session.image.size, viewSize: geo.size)
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.18))
                canvasBody(fit: fit)
                    .frame(width: fit.drawnSize.width, height: fit.drawnSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 22, y: 10)
                    .gesture(drawGesture(fit: fit))

                if session.textOrigin != nil {
                    textField(fit: fit)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func canvasBody(fit: FittedImage) -> some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.draw(Image(nsImage: session.image), in: rect)
            let scale = fit.scale
            for item in session.items {
                draw(item, in: &context, scale: scale)
            }
            if let draft = session.draft {
                draw(draft, in: &context, scale: scale)
                if session.tool == .crop, case .rect(let crop) = draft.kind {
                    drawCropMask(crop, in: &context, canvas: size, scale: scale)
                }
            }
        }
    }

    private func textField(fit: FittedImage) -> some View {
        let origin = session.textOrigin.map(fit.toView) ?? .zero
        return TextField("Type", text: $session.textDraft)
            .textFieldStyle(.plain)
            .font(.system(size: 16, weight: .semibold))
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.55)))
            .foregroundStyle(session.color)
            .frame(width: 220)
            .position(x: origin.x + 110, y: origin.y + 14)
            .onSubmit { session.commitText() }
    }

    private func drawGesture(fit: FittedImage) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if session.tool == .text { return }
                let start = fit.toImage(value.startLocation)
                let current = fit.toImage(value.location)
                session.draft = makeDraft(from: start, to: current, existing: session.draft)
            }
            .onEnded { value in
                let start = fit.toImage(value.startLocation)
                let current = fit.toImage(value.location)
                if session.tool == .text {
                    handleTap(current)
                    return
                }
                session.draft = makeDraft(from: start, to: current, existing: session.draft)
                if session.tool == .crop, case .rect(let rect) = session.draft?.kind {
                    session.applyCrop(rect)
                } else {
                    session.commitDraft()
                }
            }
    }

    private func handleTap(_ point: CGPoint) {
        session.commitText()
        session.textOrigin = point
        session.textDraft = ""
    }

    private func makeDraft(from start: CGPoint, to current: CGPoint, existing: MarkupItem?) -> MarkupItem {
        let rect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        let width: CGFloat = session.tool == .highlight ? 1 : (session.tool == .pen ? 3.5 : 3)
        switch session.tool {
        case .pen:
            var points: [CGPoint] = []
            if case .pen(let existingPoints) = existing?.kind { points = existingPoints }
            if points.isEmpty { points = [start] }
            points.append(current)
            return MarkupItem(kind: .pen(points), color: session.color, lineWidth: width)
        case .arrow:
            return MarkupItem(kind: .arrow(start, current), color: session.color, lineWidth: width)
        case .rectangle:
            return MarkupItem(kind: .rect(rect), color: session.color, lineWidth: width)
        case .ellipse:
            return MarkupItem(kind: .ellipse(rect), color: session.color, lineWidth: width)
        case .highlight:
            return MarkupItem(kind: .highlight(rect), color: session.color.opacity(1), lineWidth: width)
        case .blur:
            return MarkupItem(kind: .blur(rect), color: .black, lineWidth: width)
        case .crop:
            return MarkupItem(kind: .rect(rect), color: .white, lineWidth: 2)
        case .text:
            return MarkupItem(kind: .text(current, ""), color: session.color, lineWidth: 14)
        }
    }

    private func draw(_ item: MarkupItem, in context: inout GraphicsContext, scale: CGFloat) {
        let stroke = StrokeStyle(lineWidth: item.lineWidth * scale, lineCap: .round, lineJoin: .round)
        switch item.kind {
        case .pen(let points):
            var path = Path()
            guard let first = points.first else { return }
            path.move(to: first.scaled(scale))
            for point in points.dropFirst() { path.addLine(to: point.scaled(scale)) }
            context.stroke(path, with: .color(item.color), style: stroke)
        case .arrow(let from, let to):
            var path = Path()
            path.move(to: from.scaled(scale))
            path.addLine(to: to.scaled(scale))
            let a = atan2(to.y - from.y, to.x - from.x)
            let len: CGFloat = max(12, item.lineWidth * 4) * scale
            let spread: CGFloat = .pi / 7
            let end = to.scaled(scale)
            path.move(to: end)
            path.addLine(to: CGPoint(x: end.x - len * cos(a - spread), y: end.y - len * sin(a - spread)))
            path.move(to: end)
            path.addLine(to: CGPoint(x: end.x - len * cos(a + spread), y: end.y - len * sin(a + spread)))
            context.stroke(path, with: .color(item.color), style: stroke)
        case .rect(let rect):
            context.stroke(
                Path(roundedRect: rect.scaled(scale), cornerRadius: 2),
                with: .color(item.color),
                style: stroke
            )
        case .ellipse(let rect):
            context.stroke(Path(ellipseIn: rect.scaled(scale)), with: .color(item.color), style: stroke)
        case .highlight(let rect):
            context.fill(Path(rect.scaled(scale)), with: .color(item.color.opacity(0.38)))
        case .blur(let rect):
            context.fill(Path(rect.scaled(scale)), with: .color(.black.opacity(0.55)))
        case .text(let origin, let string):
            let resolved = context.resolve(
                Text(string)
                    .font(.system(size: max(16, item.lineWidth + 4) * scale, weight: .semibold))
                    .foregroundStyle(item.color)
            )
            context.draw(resolved, at: origin.scaled(scale), anchor: .topLeading)
        }
    }

    private func drawCropMask(_ crop: CGRect, in context: inout GraphicsContext, canvas: CGSize, scale: CGFloat) {
        let viewCrop = crop.scaled(scale)
        var mask = Path(CGRect(origin: .zero, size: canvas))
        mask.addRect(viewCrop)
        context.fill(mask, with: .color(.black.opacity(0.45)), style: FillStyle(eoFill: true))
        context.stroke(Path(viewCrop), with: .color(.white), lineWidth: 2)
    }

    private func colorsEqual(_ a: Color, _ b: Color) -> Bool {
        NSColor(a).usingColorSpace(.sRGB)?.hexString == NSColor(b).usingColorSpace(.sRGB)?.hexString
    }
}

private struct FittedImage {
    let imageSize: CGSize
    let viewSize: CGSize

    var scale: CGFloat {
        min(viewSize.width / max(imageSize.width, 1), viewSize.height / max(imageSize.height, 1))
    }

    var drawnSize: CGSize {
        CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    var origin: CGPoint {
        CGPoint(x: (viewSize.width - drawnSize.width) / 2, y: (viewSize.height - drawnSize.height) / 2)
    }

    func toImage(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: max(0, min(imageSize.width, (point.x - origin.x) / scale)),
            y: max(0, min(imageSize.height, (point.y - origin.y) / scale))
        )
    }

    func toView(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * scale + origin.x, y: point.y * scale + origin.y)
    }
}

private extension CGPoint {
    func scaled(_ scale: CGFloat) -> CGPoint { CGPoint(x: x * scale, y: y * scale) }
}

private extension CGRect {
    func scaled(_ scale: CGFloat) -> CGRect {
        CGRect(x: minX * scale, y: minY * scale, width: width * scale, height: height * scale)
    }
}

private extension NSColor {
    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return description }
        return String(format: "%0.3f-%0.3f-%0.3f", rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
    }
}
