import SwiftUI
import AppKit

enum PopoverTab: String, CaseIterable, Identifiable {
    case awake
    case stats
    case capture

    var id: String { rawValue }

    var title: String {
        switch self {
        case .awake: return "Awake"
        case .stats: return "Stats"
        case .capture: return "Capture"
        }
    }
}

struct PopoverRoot: View {
    @EnvironmentObject private var manager: CaffeinateManager
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var capture: ScreenshotController
    @State private var tab: PopoverTab = .awake

    var body: some View {
        VStack(spacing: 0) {
            header
            segmented
            Divider().padding(.horizontal, 10)
            Group {
                switch tab {
                case .awake:
                    ContentView()
                case .stats:
                    StatsView(monitor: monitor)
                case .capture:
                    CaptureView(controller: capture)
                }
            }
        }
        .frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
        .background(MenuBarPanelSizer())
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Caffeinated")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Toggle("", isOn: Binding(
                get: { manager.isActive },
                set: { manager.setActive($0) }
            ))
            .labelsHidden()
            .toggleStyle(PillToggleStyle())
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var segmented: some View {
        HStack(spacing: 2) {
            ForEach(PopoverTab.allCases) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        tab = item
                    }
                } label: {
                    Text(item.title)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(tab == item ? Color.accentColor : Color.clear)
                        )
                        .foregroundStyle(tab == item ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.14))
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
}

/// MenuBarExtra `.window` panels keep the first layout size. Resize from
/// the top so Settings / Stats / Capture can grow without covering the
/// content or leaving a clipped tab bar.
private struct MenuBarPanelSizer: NSViewRepresentable {
    func makeNSView(context: Context) -> SizerView {
        SizerView()
    }

    func updateNSView(_ nsView: SizerView, context: Context) {
        nsView.scheduleFit()
    }
}

private final class SizerView: NSView {
    private var pending: DispatchWorkItem?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleFit()
    }

    override func layout() {
        super.layout()
        scheduleFit()
    }

    func scheduleFit() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.fit()
        }
        pending = work
        DispatchQueue.main.async(execute: work)
    }

    private func fit() {
        guard let window, let content = window.contentView else { return }
        let fitting = content.fittingSize
        guard fitting.width > 1, fitting.height > 1 else { return }

        let width = max(fitting.width, 280)
        let height = fitting.height
        var frame = window.frame
        guard abs(frame.width - width) > 0.5 || abs(frame.height - height) > 0.5 else {
            return
        }

        window.contentMinSize = NSSize(width: 280, height: 1)
        window.contentMaxSize = NSSize(width: 400, height: 2000)

        let top = frame.maxY
        frame.size = NSSize(width: width, height: height)
        frame.origin.y = top - height
        window.setFrame(frame, display: true, animate: false)
    }
}
