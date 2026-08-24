import AVFoundation
import SwiftUI

/// The join preview: your camera over the meeting it is about to open.
struct CameraPreviewView: View {
    let meeting: MeetingEvent
    let now: Date
    let session: CameraPreviewSession
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
        if let capture = session.session {
            CameraFeed(session: capture)
        } else {
            VStack(spacing: Theme.Spacing.md) {
                SymbolImage(name: "video.slash", size: Theme.Size.dialogIcon)
                Text(unavailableMessage)
                    .font(Theme.Typography.rowTrailing)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Theme.Colors.textSecondary)
            .padding(Theme.Spacing.xxl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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

    private var unavailableMessage: String {
        switch session.access {
        case .denied: return "Tinycast has no access to the camera."
        case .notDetermined, .granted:
            return session.hasCamera ? "Starting the camera…" : "No camera on this Mac."
        }
    }
}

/// The one place `AVCaptureVideoPreviewLayer` is hosted; everything around it is Tinycast's own.
private struct CameraFeed: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        view.layer = preview
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view.layer as? AVCaptureVideoPreviewLayer)?.session = session
    }
}

/// `DialogButton`'s twin. Duplicated rather than shared: the dialog owns its own button, and a
/// preview that had to move with it would couple two unrelated surfaces.
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
