import Foundation

nonisolated enum ClipboardTextWorker {
    enum Failure: Error { case recognition, outputLimit }

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
        return try await withTaskCancellationHandler {
            try process.run()
            if Task.isCancelled { process.terminate() }
            let deadline = Task.detached(priority: .background) {
                do { try await Task.sleep(for: timeout) } catch { return }
                if process.isRunning { process.terminate() }
            }
            defer {
                deadline.cancel()
                if process.isRunning { process.terminate() }
                process.waitUntilExit()
                try? output.fileHandleForReading.close()
            }
            var data = Data()
            while let chunk = try output.fileHandleForReading.read(upToCount: 4096), !chunk.isEmpty {
                data.append(chunk)
                if data.count > 32_000 {
                    if process.isRunning { process.terminate() }
                    process.waitUntilExit()
                    throw Failure.outputLimit
                }
            }
            process.waitUntilExit()
            try Task.checkCancellation()
            guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else {
                throw Failure.recognition
            }
            return text
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}
