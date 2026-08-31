import SwiftUI
import AppKit

struct CaptureView: View {
    @ObservedObject var controller: ScreenshotController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let status = controller.statusMessage {
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 2)
            }
            modes
            hint
            Divider().padding(.horizontal, 10)
            options
            if controller.permissionDenied {
                permissionNote
            }
            if let last = controller.lastImage {
                Divider().padding(.horizontal, 10)
                lastCapture(last)
            }
        }
        .task { await controller.requestPermission() }
    }

    private var modes: some View {
        HStack(spacing: 8) {
            ForEach(CaptureMode.allCases) { mode in
                Button {
                    controller.begin(mode)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 16, weight: .semibold))
                        Text(mode.title)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
                .help(mode.help)
                .disabled(controller.isCapturing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var hint: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("⌃⇧4 Selection · ⌃⇧5 Window · ⌃⇧3 Screen")
            Text("Esc cancels overlay · Return confirms a selection")
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private var options: some View {
        HStack {
            Text("Copy to Clipboard")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Toggle("", isOn: $controller.copyOnCapture)
                .labelsHidden()
                .toggleStyle(PillToggleStyle(width: 30, height: 18))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var permissionNote: some View {
        Text("Allow Screen Recording for Caffeinated in System Settings to capture.")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
    }

    private func lastCapture(_ image: NSImage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last capture")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 90)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            HStack(spacing: 8) {
                Button("Edit") { controller.editLast() }
                Button("Copy") { controller.copyLast() }
                Button("Save…") { controller.saveLast() }
                Spacer()
            }
            .font(.system(size: 12))
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
