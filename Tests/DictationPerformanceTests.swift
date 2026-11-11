import AVFoundation
import Darwin
import Foundation

@main
struct DictationPerformanceTests {
    static func main() async {
        do { try await run() } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func run() async throws {
        guard CommandLine.arguments.count == 5 else { throw CocoaError(.coderInvalidValue) }
        let samples = try audio(at: URL(fileURLWithPath: CommandLine.arguments[1]))
        let bundle = URL(fileURLWithPath: CommandLine.arguments[2])
        let info = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: bundle.appending(path: "Contents/Info.plist")), format: nil)
        guard let name = (info as? [String: Any])?["CFBundleExecutable"] as? String else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[3])
        let selection = CommandLine.arguments[4]
        let models =
            selection == "all" ? DictationModel.allCases : DictationModel(rawValue: selection).map { [$0] }
        guard let models else { throw CocoaError(.coderInvalidValue) }
        print("Cold means a fresh helper; macOS's file and Core ML caches are left untouched.")
        print("| Model | Run | Load | Transcribe | Sampled peak |")
        print("| --- | --- | --- | --- | --- |")
        var transcripts = [String]()
        for model in models {
            let directory = root.appending(path: model.folderName)
            guard
                model.requiredFiles.allSatisfy({
                    FileManager.default.fileExists(atPath: directory.appending(path: $0).path)
                })
            else {
                throw DictationWire.Failure.notInstalled
            }
            let process = Process()
            let input = Pipe(), output = Pipe()
            process.executableURL = bundle.appending(path: "Contents/MacOS/\(name)")
            process.standardInput = input
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else {
                throw POSIXError(.EIO)
            }
            let exit = try process.runObservingExit()
            defer { if process.isRunning { process.terminate() }; exit.wait() }
            try? input.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
            let identifier = process.processIdentifier
            for run in ["cold", "warm"] {
                let timeout = 60 + samples.count / DictationWire.sampleRate * 2
                let deadline = Task.detached {
                    do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
                    if process.isRunning { process.terminate() }
                }
                defer { deadline.cancel() }
                let monitor = Task.detached { () -> UInt64? in
                    var peak: UInt64?
                    while !Task.isCancelled {
                        if let value = footprint(identifier) { peak = max(peak ?? 0, value) }
                        do { try await Task.sleep(for: .milliseconds(50)) } catch { break }
                    }
                    return peak
                }
                defer { monitor.cancel() }
                let started = ContinuousClock.now
                let request = DictationWire.Request(
                    id: UUID(), model: model, directory: directory,
                    sampleCount: samples.count, language: nil)
                try DictationWire.write(request, to: input.fileHandleForWriting)
                guard
                    let ready = try DictationWire.read(
                        DictationWire.Response.self, from: output.fileHandleForReading),
                    ready.id == request.id, ready.status == .ready
                else { throw DictationWire.Failure.unavailable }
                let loaded = ContinuousClock.now
                try samples.withUnsafeBytes { try input.fileHandleForWriting.write(contentsOf: $0) }
                guard
                    let result = try DictationWire.read(
                        DictationWire.Response.self, from: output.fileHandleForReading),
                    result.id == request.id, result.status == .result
                else { throw DictationWire.Failure.unavailable }
                let finished = ContinuousClock.now
                monitor.cancel()
                let peak = await monitor.value.map { "\($0 / 1_000_000) MB" } ?? "Unavailable"
                print(
                    "| \(model.title) | \(run) | \(seconds(started.duration(to: loaded))) s | "
                        + "\(seconds(loaded.duration(to: finished))) s | \(peak) |")
                transcripts.append("Transcript (\(model.rawValue), \(run)): \(result.text)")
            }
        }
        for text in transcripts { print(text) }
    }

    private static func audio(at url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0, Double(file.length) / file.processingFormat.sampleRate <= 300,
            let input = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
            let converter = AVAudioConverter(from: file.processingFormat, to: format),
            let output = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(
                    ceil(Double(file.length) * 16_000 / file.processingFormat.sampleRate)) + 64)
        else { throw CocoaError(.coderInvalidValue) }
        try file.read(into: input)
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, status in
            if supplied { status.pointee = .endOfStream; return nil }
            supplied = true
            status.pointee = .haveData
            return input
        }
        if let error { throw error }
        guard status != .error, let channel = output.floatChannelData?[0],
            (1...DictationWire.maximumSamples).contains(Int(output.frameLength))
        else { throw CocoaError(.coderInvalidValue) }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }

    private static func footprint(_ identifier: pid_t) -> UInt64? {
        var info = rusage_info_v4()
        let status = withUnsafeMutableBytes(of: &info) {
            proc_pid_rusage(
                identifier, RUSAGE_INFO_V4, $0.baseAddress!.assumingMemoryBound(to: rusage_info_t?.self))
        }
        return status == 0 ? info.ri_phys_footprint : nil
    }

    private static func seconds(_ duration: Duration) -> String {
        String(
            format: "%.3f",
            Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)
    }
}
