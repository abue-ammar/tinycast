import AVFoundation
import SwiftUI

/// What every camera surface puts above its footer: live video, or why there is none.
struct CameraStage: View {
    let feed: CameraSession.Feed
    var mirrored = true

    var body: some View {
        switch feed {
        case .live(let capture):
            CameraFeed(session: capture, mirrored: mirrored)
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
}

/// The one place `AVCaptureVideoPreviewLayer` is hosted; everything around it is Tinycast's own.
private struct CameraFeed: NSViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool

    func makeNSView(context: Context) -> NSView {
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        let view = NSView()
        // Layer-hosting, not layer-backed: set before `wantsLayer`, so AppKit never replaces it.
        view.layer = preview
        view.wantsLayer = true
        apply(mirrored, to: preview)
        return view
    }

    /// Reassigning the session rebuilds the preview connection, which blanks the layer for a frame.
    func updateNSView(_ view: NSView, context: Context) {
        guard let preview = view.layer as? AVCaptureVideoPreviewLayer else { return }
        if preview.session !== session { preview.session = session }
        apply(mirrored, to: preview)
    }

    private func apply(_ mirrored: Bool, to preview: AVCaptureVideoPreviewLayer) {
        guard let connection = preview.connection, connection.isVideoMirroringSupported else {
            return
        }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = mirrored
    }
}
