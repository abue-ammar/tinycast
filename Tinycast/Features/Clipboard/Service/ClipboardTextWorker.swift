import Foundation

/// Runs one `ClipboardTextHelper` per item, so Vision's allocations leave with the child process.
nonisolated enum ClipboardTextWorker {
    enum Failure: Error { case recognition, outputLimit }

    /// Mirrors `ClipboardTextExtractor.maximumTextBytes`: the helper is not in the app's module.
    private static let maximumOutputBytes = 32_000
    private static let readSize = 4096
    /// The read loop and `waitUntilExit` block, so they stay off the cooperative pool.
    private static let queue = DispatchQueue(
        label: "com.tinycast.clipboard-text", qos: .background, attributes: .concurrent)

    static func extract(_ item: ClipboardItem) async throws -> String {
        guard let path = item.imagePath ?? item.filePath else { return "" }
        let kind = item.kind == .image ? ClipboardFileKind.image : ClipboardFileKind.of(path: path)
        guard kind == .image || kind == .pdf else { return "" }
        let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ClipboardTextHelper")
        return try await extract(at: URL(fileURLWithPath: path), isPDF: kind == .pdf, executable: executable)
    }

    static func extract(
        at url: URL, isPDF: Bool, executable: URL, timeout: Duration = .seconds(60)
    ) async throws -> String {
        try Task.checkCancellation()
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = [isPDF ? "pdf" : "image", url.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.qualityOfService = .background
        do { try process.run() } catch { throw Failure.recognition }
        // Cancellation can land between the check above and the launch, which nothing else catches.
        if Task.isCancelled { terminate(process) }
        let deadline = Task.detached(priority: .background) {
            do { try await Task.sleep(for: timeout) } catch { return }
            terminate(process)
        }
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.async { continuation.resume(returning: collect(from: process, reading: output)) }
            }
        } onCancel: {
            terminate(process)
        }
        deadline.cancel()
        try Task.checkCancellation()
        return try result.get()
    }

    /// Blocking throughout, and the only place a helper is reaped: every exit runs the `defer`.
    private static func collect(from process: Process, reading output: Pipe) -> Result<String, Failure> {
        let reader = output.fileHandleForReading
        defer {
            terminate(process)
            process.waitUntilExit()
            try? reader.close()
        }
        var data = Data()
        do {
            while let chunk = try reader.read(upToCount: readSize), !chunk.isEmpty {
                data.append(chunk)
                if data.count > maximumOutputBytes { return .failure(.outputLimit) }
            }
        } catch {
            return .failure(.recognition)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else {
            return .failure(.recognition)
        }
        return .success(text)
    }

    /// `terminate()` traps on a process that never launched, so the state has to be asked first.
    private static func terminate(_ process: Process) {
        if process.isRunning { process.terminate() }
    }
}
