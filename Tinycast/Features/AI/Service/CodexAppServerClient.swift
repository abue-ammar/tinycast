import Foundation

@MainActor
final class CodexAppServerClient {
    enum ClientError: LocalizedError {
        case executableMissing
        case launchFailed(String)
        case processExited(String)
        case requestFailed(String)
        case timedOut

        var errorDescription: String? {
            switch self {
            case .executableMissing:
                return "Install the Codex CLI to use your Codex account."
            case .launchFailed(let detail): return "Codex could not start: \(detail)"
            case .processExited(let detail), .requestFailed(let detail): return detail
            case .timedOut: return "Codex did not respond in time."
            }
        }
    }

    private struct PendingRequest {
        let continuation: CheckedContinuation<[String: JSONValue], Error>
        let timeout: Task<Void, Never>
    }

    var onNotification: ((String, [String: JSONValue]) -> Void)?
    var onExit: ((String) -> Void)?
    /// Set for the turn that armed tools; nil declines every elicitation, as the route did before.
    var onElicitation: ((CodexElicitation) async -> Bool)?

    private let codexHome: URL?
    let workspace: URL
    private var process: Process?
    private var input: FileHandle?
    private var outputBuffer = Data()
    private var stderrBuffer = Data()
    private var nextID = 1
    private var pending: [Int: PendingRequest] = [:]
    /// What the running process was launched with. Overrides and environment are fixed at exec,
    /// so a changed list — a refreshed token included — is a relaunch, not a reconfiguration.
    private(set) var toolServers: [AIToolServer] = []

    init(codexHome: URL? = nil, workspace: URL) {
        self.codexHome = codexHome
        self.workspace = workspace
    }

    /// Process-scoped, every one of them: nothing here is ever written to the user's Codex config.
    /// `features.plugins=false` also keeps a plugin's own MCP servers out of the list below.
    nonisolated private static let configurationFlags = [
        "-c", "check_for_update_on_startup=false",
        "-c", "features.apps=false",
        "-c", "features.plugins=false",
        "-c", "features.remote_plugin=false",
        "-c", "features.plugin_sharing=false",
        "-c", "features.shell_tool=false",
        "-c", "features.unified_exec=false",
        "-c", "features.browser_use=false",
        "-c", "features.in_app_browser=false",
        "-c", "features.computer_use=false",
        "-c", "features.image_generation=false",
        "-c", "features.multi_agent=false",
        "-c", "features.hooks=false",
        "-c", "features.workspace_dependencies=false",
        "-c", "memories.use_memories=false"
    ]

    /// The servers the user configured for their own Codex, which a Tinycast thread never runs.
    /// A name this does not report cannot be disabled — the whole configuration then refuses to
    /// load — so the reading runs under the same flags the app-server will.
    nonisolated private static func foreignServerNames(
        executable: URL, workspace: URL, codexHome: URL?
    ) async -> [String] {
        var environment = ProcessInfo.processInfo.environment
        environment["NO_COLOR"] = "1"
        if let codexHome { environment["CODEX_HOME"] = codexHome.path }
        let result = await InstalledAIProbe.run(
            executable: executable, arguments: configurationFlags + ["mcp", "list", "--json"],
            workspace: workspace, environment: environment)
        guard result.status == 0 else { return [] }
        return (JSONValue(data: Data(result.output.utf8))?.arrayValue ?? []).compactMap {
            $0.objectValue?["name"]?.stringValue
        }
    }

    var isRunning: Bool { process?.isRunning == true }

    func start(toolServers: [AIToolServer] = []) async throws {
        if isRunning, self.toolServers == toolServers { return }
        guard let executable = await ExecutableLocator.locate("codex") else {
            throw ClientError.executableMissing
        }
        // A second caller may have started it during the lookup.
        if isRunning, self.toolServers == toolServers { return }
        // The list is only readable at launch, so the old process cannot be talked into it.
        if isRunning { stop() }
        guard let secrets = CodexMCPLaunch.environment(servers: toolServers) else {
            throw ClientError.launchFailed("Two MCP servers' secrets would share one variable.")
        }
        do {
            try FileManager.default.createDirectory(
                at: workspace, withIntermediateDirectories: true)
            if let codexHome {
                try FileManager.default.createDirectory(
                    at: codexHome, withIntermediateDirectories: true)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o700], ofItemAtPath: codexHome.path)
            }
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: workspace.path)
        } catch {
            throw ClientError.launchFailed("Its private support folder could not be prepared.")
        }

        // Read in a short-lived process because `mcp list` starts nothing, while the app-server
        // would have launched every one of them before anything could ask for their names.
        let foreign = await Self.foreignServerNames(
            executable: executable, workspace: workspace, codexHome: codexHome)
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executable
        process.arguments =
            Self.configurationFlags
            + CodexMCPLaunch.arguments(servers: toolServers, disabling: foreign)
            + ["app-server"]
        process.currentDirectoryURL = workspace
        let inheritedPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        let commandPaths = [
            executable.deletingLastPathComponent().path,
            "/opt/homebrew/bin",
            "/usr/local/bin"
        ]
        var environment = ProcessInfo.processInfo.environment.merging(
            [
                "NO_COLOR": "1",
                "PATH": (commandPaths + [inheritedPath]).joined(separator: ":")
            ]
        ) { _, value in value }
        environment.merge(secrets) { _, new in new }
        // Tests can isolate app-server state; production deliberately inherits the user's Codex home.
        if let codexHome { environment["CODEX_HOME"] = codexHome.path }
        process.environment = environment
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
            throw ClientError.launchFailed(error.localizedDescription)
        }
        self.process = process
        input = stdin.fileHandleForWriting
        self.toolServers = toolServers

        // A failed handshake would otherwise leave `isRunning` true on an uninitialized server.
        do {
            _ = try await request(
                method: "initialize",
                params: [
                    "clientInfo": [
                        "name": "tinycast",
                        "title": "Tinycast",
                        "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                            ?? "0"
                    ],
                    "capabilities": ["experimentalApi": false]
                ])
            try send(CodexAppServerProtocol.notification(method: "initialized"))
        } catch {
            stop()
            throw error
        }
    }

    func request(
        method: String, params: [String: Any] = [:], timeout: Duration = .seconds(15)
    ) async throws -> [String: JSONValue] {
        guard isRunning else { throw ClientError.processExited("Codex is not running.") }
        let id = nextID
        nextID += 1
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let timeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: timeout)
                    guard !Task.isCancelled else { return }
                    self?.timeoutRequest(id)
                }
                pending[id] = PendingRequest(continuation: continuation, timeout: timeoutTask)
                do {
                    try send(CodexAppServerProtocol.request(id: id, method: method, params: params))
                } catch {
                    finishRequest(id, with: .failure(error))
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                self?.finishRequest(id, with: .failure(CancellationError()))
            }
        }
    }

    func stop() {
        stop(error: ClientError.processExited("Codex stopped."))
    }

    /// Closing stdin is the clean exit — the server leaves on EOF — and SIGTERM is the backstop.
    private func stop(error: ClientError) {
        guard let process else { return }
        process.terminationHandler = nil
        cleanup(error: error)
        Task.detached {
            try? await Task.sleep(for: .seconds(1))
            if process.isRunning { process.terminate() }
        }
    }

    private func send(_ data: Data) throws {
        guard let input else { throw ClientError.processExited("Codex is not running.") }
        try input.write(contentsOf: data)
    }

    private func consumeOutput(_ data: Data) {
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer[..<newline]
            outputBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            handle(CodexAppServerProtocol.parse(Data(line)))
        }
        // An unterminated multi-megabyte line means whatever is talking is not the app server.
        guard outputBuffer.count > Self.outputLimit else { return }
        let message = "Codex sent an unterminated oversized response and was disconnected."
        onExit?(message)
        stop(error: ClientError.processExited(message))
    }

    private static let outputLimit = 8 * 1_048_576

    private func handle(_ message: CodexAppServerProtocol.Message) {
        switch message {
        case .response(let id, let result):
            finishRequest(id, with: .success(result))
        case .failure(let id, let message):
            finishRequest(id, with: .failure(ClientError.requestFailed(message)))
        case .notification(let method, let params):
            onNotification?(method, params)
        case .request(let id, let method, let params):
            guard method == "mcpServer/elicitation/request",
                let elicitation = CodexElicitation(params: params), let onElicitation
            else {
                declineServerRequest(id: id, method: method)
                return
            }
            Task { [weak self] in
                let action: CodexElicitation.Action =
                    await onElicitation(elicitation) ? .accept : .decline
                // `persist` is never answered: only Settings may change a standing decision.
                try? self?.send(
                    CodexAppServerProtocol.response(
                        id: id, result: ["action": action.rawValue]))
            }
        case .invalid:
            break
        }
    }

    private func declineServerRequest(id: CodexAppServerProtocol.RequestID, method: String) {
        let result: [String: Any]
        switch method {
        case "item/commandExecution/requestApproval", "item/fileChange/requestApproval":
            result = ["decision": "cancel"]
        case "item/permissions/requestApproval":
            result = [
                "permissions": [
                    "fileSystem": ["entries": []],
                    "network": ["enabled": false]
                ]
            ]
        case "tool/requestUserInput":
            result = ["answers": [:]]
        case "mcpServer/elicitation/request":
            // A form, or a call on a turn that armed nothing: neither is a question Tinycast asks.
            result = ["action": CodexElicitation.Action.decline.rawValue]
        default:
            try? send(
                CodexAppServerProtocol.errorResponse(
                    id: id, message: "Tinycast does not expose Codex tools."))
            return
        }
        try? send(CodexAppServerProtocol.response(id: id, result: result))
    }

    private func consumeStderr(_ data: Data) {
        stderrBuffer.append(data)
        if stderrBuffer.count > 8_192 { stderrBuffer.removeFirst(stderrBuffer.count - 8_192) }
    }

    private func timeoutRequest(_ id: Int) {
        finishRequest(id, with: .failure(ClientError.timedOut))
    }

    private func finishRequest(_ id: Int, with result: Result<[String: JSONValue], Error>) {
        guard let request = pending.removeValue(forKey: id) else { return }
        request.timeout.cancel()
        request.continuation.resume(with: result)
    }

    private func didExit(status: Int32) {
        let detail = String(decoding: stderrBuffer, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let message = detail.isEmpty ? "Codex exited with status \(status)." : detail
        onExit?(message)
        cleanup(error: ClientError.processExited(message))
    }

    private func cleanup(error: Error) {
        toolServers = []
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
