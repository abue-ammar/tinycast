import Foundation

/// A short-lived run of a command, bounded by a watchdog, an output cap and cancellation.
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

    /// `input` is written whole and the pipe closed, for a CLI that answers one request and exits.
    nonisolated static func run(
        executable: URL, arguments: [String], workspace: URL,
        environment: [String: String]? = nil, input: Data? = nil,
        timeout: Duration = .seconds(10)
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
                    process.environment =
                        environment ?? ExecutableLocator.environment(running: executable)
                    let stdin = input.map { _ in Pipe() }
                    process.standardInput = stdin ?? FileHandle.nullDevice
                    process.standardOutput = output
                    process.standardError = FileHandle.nullDevice
                    do { try process.run() } catch { return Result(status: -1, output: "") }
                    handle.set(process)
                    if let stdin, let input { Self.write(input, to: stdin, closing: true) }
                    let watchdog = Task {
                        try? await Task.sleep(for: timeout)
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

    /// Holds stdin open until a line answers, since the CLI exits once its input closes.
    nonisolated static func request(
        executable: URL, arguments: [String], workspace: URL, input: Data,
        until answered: @escaping @Sendable (String) -> Bool, timeout: Duration = .seconds(30)
    ) async -> String {
        await Task.detached {
            try? FileManager.default.createDirectory(
                at: workspace, withIntermediateDirectories: true)
            let process = Process()
            let stdin = Pipe()
            let output = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = workspace
            process.environment = ExecutableLocator.environment(running: executable)
            process.standardInput = stdin
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return "" }
            Self.write(input, to: stdin, closing: false)
            let watchdog = Task {
                try? await Task.sleep(for: timeout)
                if process.isRunning { process.terminate() }
            }
            var data = Data()
            // Not `read(upToCount:)`, which waits for a full chunk or EOF and so for the watchdog.
            while data.count < Self.maximumOutputBytes {
                let chunk = output.fileHandleForReading.availableData
                guard !chunk.isEmpty else { break }
                data.append(chunk)
                if answered(String(bytes: data, encoding: .utf8) ?? "") { break }
            }
            try? stdin.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            watchdog.cancel()
            return String(bytes: data, encoding: .utf8) ?? ""
        }.value
    }

    /// A child that exits before reading must fail the write, not SIGPIPE Tinycast.
    nonisolated private static func write(_ data: Data, to pipe: Pipe, closing: Bool) {
        _ = fcntl(pipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        try? pipe.fileHandleForWriting.write(contentsOf: data)
        if closing { try? pipe.fileHandleForWriting.close() }
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
