import Foundation

/// Runs one `ClipboardTextHelper` per item, so Vision's allocations leave with the child process.
nonisolated enum ClipboardTextWorker {
    enum Failure: Error, Equatable { case recognition, outputLimit, unreadable, accessDenied }

    /// Mirrors `ClipboardTextExtractor.maximumTextBytes`: the helper is not in the app's module.
    private static let maximumOutputBytes = 32_000
    private static let maximumFileBytes = 32_000_000
    private static let readSize = 4096
    /// The read loop and `waitUntilExit` block, so they stay off the cooperative pool.
    private static let queue = DispatchQueue(
        label: "com.tinycast.clipboard-text", qos: .background, attributes: .concurrent)

    /// UTF-8 (or Latin-1) file bytes — not Vision, so this stays in-process.
    static func extractPlainTextFile(at url: URL) throws -> String {
        try probeReadable(url)
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize,
            size <= maximumFileBytes
        else { return "" }
        let data = try mapReadError { try Data(contentsOf: url, options: [.mappedIfSafe]) }
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
        else { throw Failure.unreadable }
        return bounded(text)
    }

    private static func bounded(_ text: String) -> String {
        var prefix = text.utf8.prefix(max(0, maximumOutputBytes))
        while !prefix.isEmpty, String(bytes: prefix, encoding: .utf8) == nil {
            prefix = prefix.dropLast()
        }
        return String(bytes: prefix, encoding: .utf8) ?? ""
    }

    static func extract(_ item: ClipboardItem) async throws -> String {
        guard let path = item.imagePath ?? item.filePath else { return "" }
        let kind = item.kind == .image ? ClipboardFileKind.image : ClipboardFileKind.of(path: path)
        guard kind == .image || kind == .pdf else { return "" }
        let url = URL(fileURLWithPath: path)
        try probeReadable(url)
        let executable = Bundle.main.bundleURL.appendingPathComponent(
            "Contents/Helpers/ClipboardTextHelper")
        return try await extract(at: url, isPDF: kind == .pdf, executable: executable)
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

    /// Opens the file in-process so TCC names Tinycast, not a silent helper failure.
    static func probeReadable(_ url: URL) throws {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            _ = try handle.read(upToCount: 1)
        } catch {
            throw mapReadError(error)
        }
    }

    static func isAccessDenied(_ error: Error) -> Bool {
        if let failure = error as? Failure { return failure == .accessDenied }
        return classify(error) == .accessDenied
    }

    private static func mapReadError<T>(_ body: () throws -> T) throws -> T {
        do { return try body() } catch { throw mapReadError(error) }
    }

    private static func mapReadError(_ error: Error) -> Error {
        classify(error) == .accessDenied ? Failure.accessDenied : error
    }

    private static func classify(_ error: Error) -> Failure? {
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain,
            ns.code == Int(EACCES) || ns.code == Int(EPERM)
        {
            return .accessDenied
        }
        if ns.domain == NSCocoaErrorDomain, ns.code == NSFileReadNoPermissionError {
            return .accessDenied
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error {
            return classify(underlying)
        }
        return nil
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
