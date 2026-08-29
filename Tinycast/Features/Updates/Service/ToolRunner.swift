import Foundation

/// Drained as it arrives, so a tool outwriting the pipe buffer cannot wedge.
enum ToolRunner {
    struct Result: Sendable {
        let status: Int32
        let output: String

        var succeeded: Bool { status == 0 }

        /// The tail, which is where a tool puts the actual error.
        var tail: String {
            let lines = output.split(separator: "\n").suffix(8)
            let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? "no output" : text
        }
    }

    static func run(
        _ executable: URL, _ arguments: [String], timeout: TimeInterval = 120
    ) async throws -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let collector = OutputCollector()
        pipe.fileHandleForReading.readabilityHandler = { collector.absorb($0.availableData) }

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in
                pipe.fileHandleForReading.readabilityHandler = nil
                collector.absorb((try? pipe.fileHandleForReading.readToEnd()) ?? Data())
                continuation.resume(
                    returning: Result(status: finished.terminationStatus, output: collector.text))
            }
            do {
                try process.run()
            } catch {
                // The handler never fires for a process that never started, so resume here instead.
                pipe.fileHandleForReading.readabilityHandler = nil
                process.terminationHandler = nil
                continuation.resume(throwing: error)
                return
            }
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                guard process.isRunning else { return }
                process.terminate()
            }
        }
    }
}

/// Read from the pipe's queue and the termination handler, so the lock is load-bearing.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        // Latin-1 cannot fail, so other encodings still reach the user.
        return String(bytes: buffer, encoding: .utf8)
            ?? String(bytes: buffer, encoding: .isoLatin1) ?? ""
    }

    /// Buffers bytes, not text: a read landing mid-character would decode to a replacement.
    func absorb(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        buffer.append(data)
        lock.unlock()
    }
}
