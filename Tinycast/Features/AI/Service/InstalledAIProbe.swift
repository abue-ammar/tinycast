import Foundation

/// One short-lived run of an installed command, bounded three ways: a watchdog, an output
/// ceiling and the caller's own cancellation. Discovery uses it, and so does anything else
/// that has to ask a CLI a question before a turn starts.
enum InstalledAIProbe {
    private static let maximumOutputBytes = 2 * 1_048_576
    private static let readChunkBytes = 64 * 1_024

    struct Result: Sendable {
        let status: Int32
        let output: String
    }

    private final class ProcessHandle: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var cancelled = false

        func set(_ process: Process) {
            lock.lock()
            self.process = process
            let shouldTerminate = cancelled
            lock.unlock()
            if shouldTerminate { process.terminate() }
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let process = self.process
            lock.unlock()
            if let process, process.isRunning { process.terminate() }
        }
    }

    nonisolated static func run(
        executable: URL, arguments: [String], workspace: URL,
        environment: [String: String]? = nil
    ) async -> Result {
        let handle = ProcessHandle()
        return await withTaskCancellationHandler(
            operation: {
                // Detached because the read loop and `waitUntilExit` block: never a pool thread.
                await Task.detached {
                    try? FileManager.default.createDirectory(
                        at: workspace, withIntermediateDirectories: true)
                    let process = Process()
                    let output = Pipe()
                    process.executableURL = executable
                    process.arguments = arguments
                    process.currentDirectoryURL = workspace
                    if let environment { process.environment = environment }
                    process.standardInput = FileHandle.nullDevice
                    process.standardOutput = output
                    process.standardError = FileHandle.nullDevice
                    do { try process.run() } catch { return Result(status: -1, output: "") }
                    handle.set(process)
                    let watchdog = Task {
                        try? await Task.sleep(for: .seconds(10))
                        if process.isRunning { process.terminate() }
                    }
                    var data = Data()
                    while data.count < Self.maximumOutputBytes {
                        let count = min(Self.readChunkBytes, Self.maximumOutputBytes - data.count)
                        guard let chunk = try? output.fileHandleForReading.read(upToCount: count),
                            !chunk.isEmpty
                        else { break }
                        data.append(chunk)
                    }
                    if data.count == Self.maximumOutputBytes, process.isRunning {
                        process.terminate()
                    }
                    process.waitUntilExit()
                    watchdog.cancel()
                    return Result(
                        status: process.terminationStatus,
                        output: String(bytes: data, encoding: .utf8) ?? "")
                }.value
            },
            onCancel: {
                handle.cancel()
            })
    }

    nonisolated static func version(in output: String) -> String? {
        output.firstMatch(of: #/\d+\.\d+(?:\.\d+)?(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?/#).map {
            String($0.output)
        }
    }

    nonisolated static func loggedIn(inStatusJSON output: String) -> Bool {
        guard let data = output.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return object["loggedIn"] as? Bool == true
            || object["authenticated"] as? Bool == true
            || object["isAuthenticated"] as? Bool == true
    }

}
