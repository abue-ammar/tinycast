import AVFoundation
import SwiftUI

/// The join preview: your camera over the meeting it is about to open.
struct CameraPreviewView: View {
    let meeting: MeetingEvent
    let now: Date
    let feed: CameraPreviewSession.Feed
    let onJoin: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            stage
                .frame(
                    width: Theme.Size.cameraPreview.width,
                    height: Theme.Size.cameraPreview.height)
            footer
        }
        .frame(width: Theme.Size.cameraPreview.width)
        .background(Theme.Colors.panelScrim)
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.dialog, style: .continuous))
        .panelEntrance()
    }

    @ViewBuilder
    private var stage: some View {
        switch feed {
        case .live(let capture):
            CameraFeed(session: capture)
        case .denied:
            unavailable("Tinycast has no access to the camera.")
        case .noCamera:
            unavailable("No camera on this Mac.")
        }
    }

    private func unavailable(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            SymbolImage(name: "video.slash", size: Theme.Size.dialogIcon)
            Text(message)
                .font(Theme.Typography.rowTrailing)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(Theme.Colors.textSecondary)
        .padding(Theme.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(meeting.title)
                    .font(Theme.Typography.rowTitle)
                    .lineLimit(1)
                Text(UpcomingWindow.countdown(to: meeting.start, now: now))
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: Theme.Spacing.md)
            PreviewButton(title: "Cancel", keyCap: "esc", role: .cancel, onActivate: onCancel)
            PreviewButton(title: "Join", keyCap: "↵", role: .standard, onActivate: onJoin)
        }
        .padding(Theme.Spacing.xl)
    }
}

/// The one place `AVCaptureVideoPreviewLayer` is hosted; everything around it is Tinycast's own.
private struct CameraFeed: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        let view = NSView()
        // Layer-hosting, not layer-backed: set before `wantsLayer`, so AppKit never replaces it.
        view.layer = preview
        view.wantsLayer = true
        return view
    }

    /// Reassigning the session rebuilds the preview connection, which blanks the layer for a frame.
    func updateNSView(_ view: NSView, context: Context) {
        guard let preview = view.layer as? AVCaptureVideoPreviewLayer, preview.session !== session
        else { return }
        preview.session = session
    }
}

/// `DialogButton`'s twin, duplicated so two unrelated surfaces need not move together.
private struct PreviewButton: View {
    let title: String
    let keyCap: String
    let role: DialogAction.Role
    let onActivate: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onActivate) {
            Text(title)
                .font(Theme.Typography.bar)
                .foregroundStyle(
                    role == .cancel ? Theme.Colors.textSecondary : Theme.Colors.textPrimary
                )
                .padding(.horizontal, Theme.Spacing.xl)
                .frame(height: Theme.Size.menuButton)
                .contentShape(Capsule())
                .background(Capsule().fill(hovered ? Theme.Colors.menuHover : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .frosted(in: Capsule())
        .tooltip(keyCap)
    }
}
