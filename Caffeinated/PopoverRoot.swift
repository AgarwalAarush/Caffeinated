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

    var symbol: String {
        switch self {
        case .awake: return "cup.and.saucer.fill"
        case .stats: return "chart.bar.fill"
        case .capture: return "camera.viewfinder"
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
            .frame(minHeight: 220, alignment: .top)

            Divider()
            tabBar
        }
        .frame(width: 280)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(PopoverTab.allCases) { item in
                Button {
                    tab = item
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 13, weight: .semibold))
                        Text(item.title)
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(tab == item ? Color.accentColor : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
    }
}
