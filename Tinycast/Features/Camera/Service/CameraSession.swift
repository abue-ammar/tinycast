import AVFoundation
import AppKit

/// `AVCaptureSession` is not `Sendable`, so the blocking calls go off main behind a box.
@MainActor
final class CameraSession {
    /// What the session is built for; taking a photo costs a larger preset and an extra output.
    enum Purpose {
        case preview
        case capture
    }

    /// Settled before the panel opens, so it never swaps a stage out from under the user.
    enum Feed {
        case live(AVCaptureSession)
        case denied
        case noCamera
    }

    /// Every camera the Mac offers right now, in the order `switchToNextDevice` cycles them.
    static var devices: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video, position: .unspecified
        ).devices
    }

    private let purpose: Purpose
    private var capture: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var device: AVCaptureDevice?
    private var pendingPhoto: PhotoCapture?

    init(_ purpose: Purpose = .preview) {
        self.purpose = purpose
    }

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

    var hasMultipleDevices: Bool { Self.devices.count > 1 }

    /// Only the input swaps: the session keeps running, so the stage never blanks to black.
    func switchToNextDevice() async {
        let devices = Self.devices
        guard devices.count > 1, let capture, let device else { return }
        // A device the discovery session does not list wraps to the first one rather than sticking.
        let index = devices.firstIndex(of: device) ?? devices.count - 1
        let next = devices[(index + 1) % devices.count]
        guard let input = try? AVCaptureDeviceInput(device: next) else { return }
        let box = CaptureBox(session: capture, input: input)
        await Task.detached {
            box.session.beginConfiguration()
            for existing in box.session.inputs { box.session.removeInput(existing) }
            if let input = box.input, box.session.canAddInput(input) {
                box.session.addInput(input)
            }
            box.session.commitConfiguration()
        }.value
        self.device = next
    }

    /// PNG rather than the camera's own encoding, so the clipboard history records it as an image.
    func capturePhoto(mirrored: Bool) async -> Data? {
        guard let photoOutput, capture?.isRunning == true else { return nil }
        if let connection = photoOutput.connection(with: .video),
            connection.isVideoMirroringSupported
        {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }
        let capture = PhotoCapture()
        pendingPhoto = capture
        defer { pendingPhoto = nil }
        guard let encoded = await capture.take(from: photoOutput) else { return nil }
        return await Task.detached {
            NSBitmapImageRep(data: encoded)?.representation(using: .png, properties: [:])
        }.value
    }

    private func configure() -> AVCaptureSession? {
        guard let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device)
        else { return nil }
        let capture = AVCaptureSession()
        capture.sessionPreset = purpose == .capture ? .photo : .medium
        guard capture.canAddInput(input) else { return nil }
        capture.addInput(input)
        self.device = device
        guard purpose == .capture else { return capture }
        let output = AVCapturePhotoOutput()
        guard capture.canAddOutput(output) else { return capture }
        capture.addOutput(output)
        photoOutput = output
        return capture
    }
}

/// Confined to this file: those calls are all that touch capture objects off main.
private struct CaptureBox: @unchecked Sendable {
    let session: AVCaptureSession
    var input: AVCaptureDeviceInput?
}

/// Unchecked because the continuation is written on main and read once on AVFoundation's queue.
private final class PhotoCapture: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<Data?, Never>?

    @MainActor
    func take(from output: AVCapturePhotoOutput) async -> Data? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        continuation?.resume(returning: error == nil ? photo.fileDataRepresentation() : nil)
        continuation = nil
    }
}
