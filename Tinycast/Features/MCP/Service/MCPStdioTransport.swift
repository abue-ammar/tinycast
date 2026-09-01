import Foundation

/// A local server over its own stdin/stdout, one newline-delimited JSON-RPC message per line.
@MainActor
final class MCPStdioTransport: MCPTransport {
    private struct PendingRequest {
        let continuation: CheckedContinuation<JSONValue, Error>
        let timeout: Task<Void, Never>
    }

    var onNotification: ((String, JSONValue) -> Void)?
    var onExit: ((String) -> Void)?

    private let command: String
    private let arguments: [String]
    private let environment: [String: String]
    private var process: Process?
    private var input: FileHandle?
    private var outputBuffer = Data()
    private var stderrBuffer = Data()
    private var nextID = 1
    private var pending: [Int: PendingRequest] = [:]

    /// An unterminated line this long means whatever is talking is not an MCP server.
    private static let outputLimit = 8 * 1_048_576
    private static let stderrLimit = 8_192

    init(command: String, arguments: [String], environment: [String: String]) {
        self.command = command
        self.arguments = arguments
        self.environment = environment
    }

    var isRunning: Bool { process?.isRunning == true }

    func connect() async throws {
        if isRunning { return }
        guard let executable = await ExecutableLocator.locate(command) else {
            throw MCPTransportError.launchFailed("`\(command)` was not found on this Mac.")
        }
        // A second caller may have started it during the lookup.
        if isRunning { return }
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.environment = Self.launchEnvironment(executable: executable, adding: environment)
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in self?.consumeOutput(data) }
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in self?.consumeStderr(data) }
        }
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { @MainActor in self?.didExit(status: status) }
        }
        do {
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            throw MCPTransportError.launchFailed(error.localizedDescription)
        }
        self.process = process
        input = stdin.fileHandleForWriting
    }

    func request(_ method: String, _ params: [String: Any]?) async throws -> JSONValue {
        guard isRunning else { throw MCPTransportError.notRunning }
        let id = nextID
        nextID += 1
        let timeout: Duration = method == "tools/call" ? .seconds(60) : .seconds(15)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let watchdog = Task { [weak self] in
                    try? await Task.sleep(for: timeout)
                    guard !Task.isCancelled else { return }
                    self?.finish(id, with: .failure(MCPTransportError.timedOut))
                }
                pending[id] = PendingRequest(continuation: continuation, timeout: watchdog)
                do {
                    try send(
                        MCPProtocol.request(
                            id: id, method: method, params: params, newlineTerminated: true))
                } catch {
                    finish(id, with: .failure(error))
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor in self?.finish(id, with: .failure(CancellationError())) }
        }
    }

    func notify(_ method: String, _ params: [String: Any]?) throws {
        try send(MCPProtocol.notification(method: method, params: params, newlineTerminated: true))
    }

    func close() {
        stop(error: MCPTransportError.notRunning)
    }

    /// Closing stdin is the clean exit — the server leaves on EOF — and SIGTERM is the backstop.
    private func stop(error: Error) {
        guard let process else { return }
        process.terminationHandler = nil
        cleanup(error: error)
        Task.detached {
            try? await Task.sleep(for: .seconds(1))
            if process.isRunning { process.terminate() }
        }
    }

    /// A GUI app inherits Finder's PATH, so the server's own toolchain has to be put back on it.
    private static func launchEnvironment(
        executable: URL, adding environment: [String: String]
    ) -> [String: String] {
        let inherited = ProcessInfo.processInfo.environment
        let paths =
            [executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin"]
            + [inherited["PATH"] ?? "/usr/bin:/bin"]
        return
            inherited
            .merging(environment) { _, server in server }
            .merging(["NO_COLOR": "1", "PATH": paths.joined(separator: ":")]) { _, new in new }
    }

    private func send(_ data: Data) throws {
        guard let input else { throw MCPTransportError.notRunning }
        try input.write(contentsOf: data)
    }

    private func consumeOutput(_ data: Data) {
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer[..<newline]
            outputBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            handle(MCPProtocol.parse(Data(line)))
        }
        guard outputBuffer.count > Self.outputLimit else { return }
        let message = "The server sent an unterminated oversized response and was disconnected."
        onExit?(message)
        stop(error: MCPTransportError.requestFailed(message))
    }

    private func handle(_ message: MCPProtocol.Message) {
        switch message {
        case .response(let id, let result):
            finish(id, with: .success(result))
        case .failure(let id, let message):
            finish(id, with: .failure(MCPTransportError.requestFailed(message)))
        case .notification(let method, let params):
            onNotification?(method, params)
        case .request(let id, _):
            try? send(MCPProtocol.decline(id: id, newlineTerminated: true))
        case .invalid:
            break
        }
    }

    /// Termination can beat the last read, and what a server printed on its way out is the reason.
    private func drainStderr() {
        guard let handle = (process?.standardError as? Pipe)?.fileHandleForReading else { return }
        handle.readabilityHandler = nil
        consumeStderr(handle.readDataToEndOfFile())
    }

    private func consumeStderr(_ data: Data) {
        guard !data.isEmpty else { return }
        stderrBuffer.append(data)
        guard stderrBuffer.count > Self.stderrLimit else { return }
        stderrBuffer.removeFirst(stderrBuffer.count - Self.stderrLimit)
    }

    private func finish(_ id: Int, with result: Result<JSONValue, Error>) {
        guard let request = pending.removeValue(forKey: id) else { return }
        request.timeout.cancel()
        request.continuation.resume(with: result)
    }

    private func didExit(status: Int32) {
        drainStderr()
        let detail = String(decoding: stderrBuffer, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let message = detail.isEmpty ? "The server exited with status \(status)." : detail
        // Pending calls are failed before the owner hears, or closing would overwrite the reason.
        cleanup(error: MCPTransportError.requestFailed(message))
        onExit?(message)
    }

    private func cleanup(error: Error) {
        process?.terminationHandler = nil
        (process?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        (process?.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        try? input?.close()
        process = nil
        input = nil
        outputBuffer.removeAll(keepingCapacity: false)
        stderrBuffer.removeAll(keepingCapacity: false)
        let requests = pending
        pending.removeAll()
        for request in requests.values {
            request.timeout.cancel()
            request.continuation.resume(throwing: error)
        }
    }
}
