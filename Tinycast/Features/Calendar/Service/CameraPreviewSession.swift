import AVFoundation

/// `AVCaptureSession` is not `Sendable`, so only the two blocking calls go off main.
@MainActor
final class CameraPreviewSession {
    /// Settled before the panel opens, so it never swaps a stage out from under the user.
    enum Feed {
        case live(AVCaptureSession)
        case denied
        case noCamera
    }

    private var capture: AVCaptureSession?

    /// Blocking on `startRunning` is the point: the first frame is video, not black.
    func start() async -> Feed {
        var access = Permissions.cameraAccess()
        if access == .notDetermined {
            _ = await Permissions.requestCameraAccess()
            access = Permissions.cameraAccess()
        }
        guard access == .granted else { return .denied }
        guard let capture = capture ?? configure() else { return .noCamera }
        self.capture = capture
        guard !capture.isRunning else { return .live(capture) }
        let box = CaptureBox(session: capture)
        await Task.detached { box.session.startRunning() }.value
        return .live(capture)
    }

    func stop() {
        guard let capture, capture.isRunning else { return }
        // The camera light must go out with the panel, so this is never left to deallocation.
        let box = CaptureBox(session: capture)
        Task.detached { box.session.stopRunning() }
    }

    private func configure() -> AVCaptureSession? {
        guard let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device)
        else { return nil }
        let capture = AVCaptureSession()
        capture.sessionPreset = .medium
        guard capture.canAddInput(input) else { return nil }
        capture.addInput(input)
        return capture
    }
}

/// Confined to this file: those two calls are all that touch the session off main.
private struct CaptureBox: @unchecked Sendable {
    let session: AVCaptureSession
}
