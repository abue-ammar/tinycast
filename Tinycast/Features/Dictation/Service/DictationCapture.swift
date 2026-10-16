import AVFoundation
import AudioToolbox
import CoreMedia

@MainActor
final class DictationCapture {
    enum Failure: LocalizedError {
        case microphoneUnavailable
        case microphoneDenied
        case captureUnavailable

        var errorDescription: String? {
            switch self {
            case .microphoneUnavailable: String(localized: "No microphone is available.")
            case .microphoneDenied:
                String(localized: "Allow Tinycast to use the microphone in System Settings.")
            case .captureUnavailable: String(localized: "Couldn't start recording from this microphone.")
            }
        }
    }

    static var microphones: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified
        ).devices
    }

    var onLevels: (([Float]) -> Void)?
    var onLimit: (() -> Void)?

    private var session: AVCaptureSession?
    private var output: AVCaptureAudioDataOutput?
    private var collector: AudioCollector?

    func start(microphoneID: String?) async throws {
        let permission = AVCaptureDevice.authorizationStatus(for: .audio)
        let granted: Bool
        if permission == .notDetermined {
            granted = await AVCaptureDevice.requestAccess(for: .audio)
        } else {
            granted = permission == .authorized
        }
        guard granted else { throw Failure.microphoneDenied }
        let device =
            microphoneID.map { id in Self.microphones.first { $0.uniqueID == id } }
            ?? AVCaptureDevice.default(for: .audio)
        guard let device else { throw Failure.microphoneUnavailable }
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            throw Failure.captureUnavailable
        }

        let capture = AVCaptureSession()
        let output = AVCaptureAudioDataOutput()
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: DictationWire.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false
        ]
        guard capture.canAddInput(input), capture.canAddOutput(output) else {
            throw Failure.captureUnavailable
        }
        capture.addInput(input)
        capture.addOutput(output)
        let collector = try AudioCollector(
            onLevels: { [weak self] levels in
                Task { @MainActor [weak self] in self?.onLevels?(levels) }
            },
            onLimit: { [weak self] in
                Task { @MainActor [weak self] in self?.onLimit?() }
            })
        output.setSampleBufferDelegate(collector, queue: collector.queue)
        self.session = capture
        self.output = output
        self.collector = collector
        let box = CaptureSessionBox(capture)
        await Task.detached { box.session.startRunning() }.value
        guard capture.isRunning else {
            _ = await stop()
            throw Failure.captureUnavailable
        }
    }

    func stop() async -> [Float] {
        guard let session else { return [] }
        self.session = nil
        let box = CaptureSessionBox(session)
        await Task.detached { box.session.stopRunning() }.value
        output?.setSampleBufferDelegate(nil, queue: nil)
        output = nil
        let samples = collector?.finish() ?? []
        collector = nil
        return samples
    }

    func snapshot() -> [Float] {
        guard session != nil else { return [] }
        return collector?.snapshot() ?? []
    }
}

// Configuration stays on main; only start/stop run off-main, in sequence.
private struct CaptureSessionBox: @unchecked Sendable {
    let session: AVCaptureSession
    init(_ session: AVCaptureSession) { self.session = session }
}

// Sample buffers and mutable state are confined to the delegate queue, including finish().
private final class AudioCollector: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate,
    @unchecked Sendable
{
    let queue = DispatchQueue(label: "com.tinycast.dictation.audio")
    private var samples: [Float] = []
    private var displayedLevels: [Float]
    private let spectrum: DictationSpectrum
    private var waveformStartIndex = 0
    private var lastLevelUpdate: TimeInterval = 0
    private var reachedLimit = false
    private let onLevels: @Sendable ([Float]) -> Void
    private let onLimit: @Sendable () -> Void

    init(onLevels: @escaping @Sendable ([Float]) -> Void, onLimit: @escaping @Sendable () -> Void) throws {
        spectrum = try DictationSpectrum()
        displayedLevels = [Float](repeating: 0, count: DictationSpectrum.barCount)
        self.onLevels = onLevels
        self.onLimit = onLimit
    }

    func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        var blockBuffer: CMBlockBuffer?
        var bufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: 0, mData: nil))
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: &bufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0, blockBufferOut: &blockBuffer)
        guard status == noErr, let data = bufferList.mBuffers.mData else { return }
        let count = Int(bufferList.mBuffers.mDataByteSize) / MemoryLayout<Float>.size
        guard count > 0, samples.count < DictationWire.maximumSamples else { return }
        let floats = data.assumingMemoryBound(to: Float.self)
        let accepted = min(count, DictationWire.maximumSamples - samples.count)
        samples.append(contentsOf: UnsafeBufferPointer(start: floats, count: accepted))
        if samples.count == DictationWire.maximumSamples, !reachedLimit {
            reachedLimit = true
            onLimit()
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastLevelUpdate >= 0.05 else { return }
        lastLevelUpdate = now
        let levels = spectrum.levels(for: samples[waveformStartIndex...])
        waveformStartIndex = samples.count
        for index in levels.indices {
            let response: Float = levels[index] > displayedLevels[index] ? 0.6 : 0.25
            displayedLevels[index] += (levels[index] - displayedLevels[index]) * response
        }
        onLevels(displayedLevels)
    }

    func finish() -> [Float] { queue.sync { samples } }

    func snapshot() -> [Float] { queue.sync { samples } }
}
