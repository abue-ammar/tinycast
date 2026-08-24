import AVFoundation

/// The capture session behind the join preview. `AVCaptureSession` is not `Sendable`, so it stays
/// main-actor isolated; only `startRunning` — which blocks — goes off.
@MainActor
@Observable
final class CameraPreviewSession {
    private(set) var access: CameraAccess = Permissions.cameraAccess()
    /// False when the Mac has no camera at all, which reads differently from a refused one.
    private(set) var hasCamera = true

    @ObservationIgnored private(set) var session: AVCaptureSession?

    /// Asks the first time and configures once; the grant is process-wide after that.
    func start() async {
        access = Permissions.cameraAccess()
        if access == .notDetermined {
            _ = await Permissions.requestCameraAccess()
            access = Permissions.cameraAccess()
        }
        guard access == .granted else { return }
        guard let session = session ?? configure() else { return }
        self.session = session
        guard !session.isRunning else { return }
        let box = CaptureBox(session: session)
        await Task.detached { box.session.startRunning() }.value
    }

    func stop() {
        guard let session, session.isRunning else { return }
        // The camera light must go out with the panel, so this is never left to deallocation.
        let box = CaptureBox(session: session)
        Task.detached { box.session.stopRunning() }
    }

    private func configure() -> AVCaptureSession? {
        guard let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device)
        else {
            hasCamera = false
            return nil
        }
        let session = AVCaptureSession()
        session.sessionPreset = .medium
        guard session.canAddInput(input) else {
            hasCamera = false
            return nil
        }
        session.addInput(input)
        return session
    }
}

/// `startRunning` and `stopRunning` block, and Apple's own samples drive both off the main queue —
/// but `AVCaptureSession` carries no `Sendable` annotation. This box is confined to this file, and
/// those two calls are the only things that ever touch the session off the main actor.
private struct CaptureBox: @unchecked Sendable {
    let session: AVCaptureSession
}
