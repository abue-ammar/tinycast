import Foundation

struct InstalledCLIProvider: AIProvider {
    private let runner: InstalledCLITurnRunner

    @MainActor
    init(
        kind: InstalledAIKind, executable: URL?, model: String, effort: String?, workspace: URL,
        toolServers: AIToolServerSession? = nil
    ) {
        runner = InstalledCLITurnRunner(
            kind: kind, executable: executable, model: model, effort: effort,
            workspace: workspace, toolServers: toolServers)
    }

    func stream(_ request: AIRequest) -> AIProviderStream {
        runner.stream(request)
    }
}

@MainActor
private final class InstalledCLITurnRunner {
    private static let safetyInstructions = """
        You are generating text inside Tinycast. Do not invoke tools, read files, inspect the \
        environment, access external resources, or modify anything. Use only the conversation and \
        instructions in this request.
        """
    /// The same boundary, for the one route that is handed tools: everything else stays off.
    private static let toolSafetyInstructions = """
        You are generating text inside Tinycast. The only tools you may use are the MCP tools \
        supplied with this request. Do not read files, inspect the environment, access external \
        resources, or modify anything else.
        """
    private static let openCodeConfiguration = """
        {"permission":"deny","share":"disabled","agent":{"build":{"permission":"deny"},\
        "plan":{"permission":"deny"}}}
        """

    private static var maximumPartialLineBytes: Int {
        if let raw = ProcessInfo.processInfo.environment["TC_INSTALLED_MAX_LINE_BYTES"],
            let value = Int(raw), value > 0
        {
            return value
        }
        return 8 * 1_048_576
    }

    private final class TurnToken: Sendable {}

    private let kind: InstalledAIKind
    private let configuredExecutable: URL?
    private let model: String
    private let effort: String?
    private let workspace: URL
    private let toolServers: AIToolServerSession?

    private var token: TurnToken?
    private var process: Process?
    private var continuation: AIProviderStream.Continuation?
    private var outputBuffer = Data()
    private var errorBuffer = Data()
    private var turnSessionID: String?
    private var promptFileURL: URL?
    private var activeExecutable: URL?
    /// What this turn armed, empty on every route and every turn that offers no server.
    private var activeServers: [AIToolServer] = []
    private var mcpConfigURL: URL?
    private var input: FileHandle?
    private var consents: [Task<Void, Never>] = []
    /// Chained rather than concurrent: two writes racing the same pipe would interleave a line.
    private var writes: Task<Void, Never> = Task {}

    init(
        kind: InstalledAIKind, executable: URL?, model: String, effort: String?, workspace: URL,
        toolServers: AIToolServerSession? = nil
    ) {
        self.kind = kind
        configuredExecutable = executable
        self.model = model
        self.effort = effort
        self.workspace = workspace
        self.toolServers = toolServers
    }

    nonisolated func stream(_ request: AIRequest) -> AIProviderStream {
        AIProviderStream { continuation in
            let token = TurnToken()
            let task = Task { [weak self] in
                await self?.start(request, continuation: continuation, token: token)
            }
            continuation.onTermination = { [weak self] _ in
                task.cancel()
                Task { @MainActor in self?.cancel(token) }
            }
        }
    }

    private func start(
        _ request: AIRequest, continuation: AIProviderStream.Continuation, token: TurnToken
    ) async {
        guard kind != .codex else {
            continuation.finish(
                throwing: AIProviderError.unavailable("Codex requires its app-server adapter."))
            return
        }
        guard
            request.messages.contains(where: {
                $0.role == .user
                    && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
        else {
            continuation.finish(
                throwing: AIProviderError.unavailable("There is no user message to send."))
            return
        }
        let resolvedExecutable: URL?
        if let configuredExecutable {
            resolvedExecutable = configuredExecutable
        } else {
            resolvedExecutable = await ExecutableLocator.locate(
                kind.command, extraHomePaths: kind.extraExecutablePaths)
        }
        guard let executable = resolvedExecutable else {
            continuation.finish(
                throwing: AIProviderError.unavailable(
                    "Install " + kind.title + " before using this model."))
            return
        }
        if Task.isCancelled {
            continuation.finish(throwing: CancellationError())
            return
        }
        cancelActiveTurn()
        do {
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: workspace.path)
        } catch {
            continuation.finish(
                throwing: AIProviderError.unavailable(
                    "Tinycast could not prepare its private AI workspace."))
            return
        }

        activeServers = await resolvedToolServers()
        let prompt = prompt(for: request)
        var configURL: URL?
        if !activeServers.isEmpty {
            let url = workspace.appending(path: ClaudeMCPLaunch.configurationFileName())
            do {
                try await Self.writePrivateFile(
                    ClaudeMCPLaunch.configuration(servers: activeServers), to: url)
            } catch {
                try? FileManager.default.removeItem(at: url)
                activeServers = []
                continuation.finish(
                    throwing: AIProviderError.unavailable(
                        "Tinycast could not write its private MCP configuration."))
                return
            }
            configURL = url
        }

        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executable
        process.currentDirectoryURL = workspace
        process.environment = environment(for: executable)
        var grokPrompt: URL?
        if kind == .grok {
            let url = workspace.appending(path: "tinycast-prompt-\(UUID().uuidString).txt")
            do {
                try await Self.writePromptFile(prompt, to: url)
            } catch {
                try? FileManager.default.removeItem(at: url)
                continuation.finish(
                    throwing: AIProviderError.unavailable(
                        "Tinycast could not write its private AI prompt."))
                return
            }
            grokPrompt = url
            process.standardInput = FileHandle.nullDevice
        } else {
            process.standardInput = stdin
        }
        process.arguments = arguments(promptFile: grokPrompt, mcpConfig: configURL)
        process.standardOutput = stdout
        process.standardError = stderr
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in self?.consume(data, token: token) }
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in self?.consumeError(data, token: token) }
        }
        // Strong on purpose: the runner must outlive its provider to tear the turn down on exit.
        process.terminationHandler = { [self] process in
            let status = process.terminationStatus
            Task { @MainActor in self.didExit(status: status, token: token) }
        }
        if Task.isCancelled {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            process.terminationHandler = nil
            if let grokPrompt { try? FileManager.default.removeItem(at: grokPrompt) }
            if let configURL { try? FileManager.default.removeItem(at: configURL) }
            continuation.finish(throwing: CancellationError())
            return
        }
        do {
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            process.terminationHandler = nil
            if let grokPrompt { try? FileManager.default.removeItem(at: grokPrompt) }
            if let configURL { try? FileManager.default.removeItem(at: configURL) }
            continuation.finish(
                throwing: AIProviderError.responseFailed(
                    kind.title + " could not start: " + error.localizedDescription))
            return
        }
        promptFileURL = grokPrompt
        mcpConfigURL = configURL
        self.process = process
        activeExecutable = executable
        self.token = token
        self.continuation = continuation
        guard kind != .grok else { return }
        input = stdin.fileHandleForWriting
        // A tool loop answers on the same pipe, so a stream-json turn keeps stdin open for it.
        if activeServers.isEmpty {
            write(Data(prompt.utf8), closing: true)
        } else if let line = ClaudeControlProtocol.userMessage(prompt) {
            write(line, closing: false)
        } else {
            fail("Tinycast could not frame the request for " + kind.title + ".")
        }
    }

    /// A pipe write past the buffer blocks until the child drains it, so never on the main actor.
    private func write(_ data: Data, closing: Bool) {
        guard let input else { return }
        let previous = writes
        writes = Task.detached {
            await previous.value
            try? input.write(contentsOf: data)
            if closing { try? input.close() }
        }
    }

    nonisolated private static func writePromptFile(_ prompt: String, to url: URL) async throws {
        try await Task.detached {
            try Data(prompt.utf8).write(to: url)
        }.value
    }

    /// Created `0600`: `createFile` writes a `0644` temporary first and restricts it after.
    nonisolated private static func writePrivateFile(_ text: String, to url: URL) async throws {
        try await Task.detached {
            let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
            guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
            let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            try file.write(contentsOf: Data(text.utf8))
            try file.close()
        }.value
    }

    /// What this turn may offer: nothing at all unless the route is Claude and MCP armed it.
    private func resolvedToolServers() async -> [AIToolServer] {
        guard kind == .claude, let toolServers, !InstalledAIManager.hasManagedMCPPolicy else {
            return []
        }
        return await toolServers.servers()
    }

    private func arguments(promptFile: URL? = nil, mcpConfig: URL? = nil) -> [String] {
        switch kind {
        case .claude:
            var result = [
                "-p",
                "--model", model,
                "--input-format", mcpConfig == nil ? "text" : "stream-json",
                "--output-format", "stream-json",
                "--verbose",
                "--include-partial-messages",
                "--no-session-persistence",
                "--disable-slash-commands",
                "--tools", "",
                // `--bare` is not among these: it refuses the OAuth sign-in this whole route reuses.
                "--no-chrome",
                "--system-prompt",
                mcpConfig == nil ? Self.safetyInstructions : Self.toolSafetyInstructions
            ]
            if let mcpConfig {
                result += ClaudeMCPLaunch.arguments(
                    configurationPath: mcpConfig.path, handles: activeServers.map(\.handle),
                    rounds: toolServers?.rounds ?? 1)
            } else {
                // A route with nothing to call keeps every tool off and the turn to one request.
                result += ["--disallowedTools", "*", "--max-turns", "1"]
                // The CLI rejects both flags while an admin's managed MCP policy is installed.
                if !InstalledAIManager.hasManagedMCPPolicy {
                    result += ["--strict-mcp-config", "--mcp-config", #"{"mcpServers":{}}"#]
                }
            }
            if let effort { result += ["--effort", effort] }
            return result
        case .openCode:
            var result = [
                "run", "--pure", "--format", "json", "--model", model,
                "--dir", workspace.path, "--title", "Tinycast"
            ]
            if let effort { result += ["--variant", effort] }
            return result
        case .grok:
            var result = [
                "--prompt-file", promptFile?.path ?? "",
                "--output-format", "streaming-messages-json",
                "--include-partial-messages",
                "--model", model,
                "--max-turns", "1",
                "--no-subagents",
                "--disable-web-search",
                "--no-plan",
                "--permission-mode", "dontAsk",
                "--tools", "",
                "--deny", "*",
                "--disallowed-tools", "Agent",
                // strict refuses to start if /var/run/docker.sock is a symlink.
                "--sandbox", "workspace",
                "--verbatim",
                "--cwd", workspace.path,
                "--rules", Self.safetyInstructions
            ]
            if let effort { result += ["--effort", effort] }
            return result
        case .cursor:
            return [
                "-p",
                "--mode", "ask",
                "--trust",
                "--workspace", workspace.path,
                "--model", model,
                "--output-format", "stream-json",
                "--stream-partial-output"
            ]
        case .codex:
            return []
        }
    }

    private func environment(for executable: URL) -> [String: String] {
        let inheritedPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        var result = ProcessInfo.processInfo.environment.merging(
            [
                "NO_COLOR": "1",
                "PATH": executable.deletingLastPathComponent().path + ":" + inheritedPath
            ]
        ) { _, value in value }
        switch kind {
        case .claude:
            result["CLAUDE_CODE_SKIP_PROMPT_HISTORY"] = "1"
            result["ENABLE_CLAUDEAI_MCP_SERVERS"] = "false"
        case .openCode:
            result["OPENCODE_CONFIG_CONTENT"] = Self.openCodeConfiguration
            result["OPENCODE_AUTO_SHARE"] = "false"
            result["OPENCODE_DISABLE_AUTOUPDATE"] = "true"
        case .grok:
            result["GROK_DISABLE_AUTOUPDATER"] = "1"
            result["GROK_AGENT_DASHBOARD"] = "0"
        case .cursor, .codex:
            break
        }
        return result
    }

    private func prompt(for request: AIRequest) -> String {
        var sections = [
            activeServers.isEmpty ? Self.safetyInstructions : Self.toolSafetyInstructions
        ]
        if let instructions = request.instructions?.trimmingCharacters(in: .whitespacesAndNewlines),
            !instructions.isEmpty
        {
            sections.append("Instructions:\n" + instructions)
        }
        for message in request.messages {
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let role: String
            switch message.role {
            case .system: role = "System instructions"
            case .user: role = "User"
            case .assistant: role = "Assistant"
            case .tool: role = "Tool result"
            }
            sections.append(role + ":\n" + text)
        }
        return sections.joined(separator: "\n\n")
    }

    private func consume(_ data: Data, token: TurnToken) {
        guard self.token === token else { return }
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer[..<newline]
            if line.count > Self.maximumPartialLineBytes {
                fail(kind.title + " returned an oversized response.")
                return
            }
            outputBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            apply(
                InstalledAIStreamDecoder.decode(
                    Data(line), kind: kind, servers: activeServers), token: token)
        }
        if outputBuffer.count > Self.maximumPartialLineBytes {
            fail(kind.title + " returned an oversized response.")
        }
    }

    private func apply(_ frame: InstalledAIStreamFrame, token: TurnToken) {
        if let sessionID = frame.sessionID { turnSessionID = sessionID }
        if let request = frame.controlRequest {
            answer(request, token: token)
            return
        }
        if let id = frame.unsupportedRequestID {
            let refusal = "Tinycast does not answer this request."
            if let line = ClaudeControlProtocol.error(to: id, message: refusal) {
                write(line, closing: false)
            }
            return
        }
        for event in frame.events { continuation?.yield(event) }
        if frame.stoppedAtRoundCap {
            fail("Stopped after \(toolServers?.rounds ?? 1) rounds of tool calls.")
        } else if let error = frame.error {
            fail(error)
        } else if frame.completed {
            continuation?.yield(.finished)
            continuation?.finish()
            continuation = nil
            // A stream-json turn is answered; closing stdin is what lets the child leave.
            write(Data(), closing: true)
        }
    }

    /// The reader's decision, through the same trust policy and dialog the BYOK loop asks with.
    private func answer(_ request: ClaudeControlProtocol.Request, token: TurnToken) {
        consents.append(Task { [weak self] in
            let allowed = await self?.toolServers?.consent(request.call) ?? false
            guard let self, self.token === token else { return }
            guard
                let line = ClaudeControlProtocol.response(
                    to: request, allowed: allowed,
                    message: "The user declined this tool call.")
            else { return }
            self.write(line, closing: false)
        })
    }

    /// A question still waiting its turn belongs to a turn that is over, so it is never asked.
    private func cancelConsents() {
        for consent in consents { consent.cancel() }
        consents = []
    }

    private func consumeError(_ data: Data, token: TurnToken) {
        guard self.token === token else { return }
        errorBuffer.append(data)
        if errorBuffer.count > 16_384 { errorBuffer.removeFirst(errorBuffer.count - 16_384) }
    }

    private func didExit(status: Int32, token: TurnToken) {
        guard self.token === token else { return }
        if continuation != nil {
            let detail = (String(bytes: errorBuffer, encoding: .utf8) ?? "")
                .replacingOccurrences(
                    of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = kind.title + " exited with status " + String(status) + "."
            fail(detail.isEmpty ? fallback : detail)
        }
        deleteTurnSession()
        cleanup()
    }

    private func fail(_ message: String) {
        continuation?.finish(throwing: AIProviderError.responseFailed(message))
        continuation = nil
        process?.terminate()
    }

    private func cancel(_ token: TurnToken) {
        guard self.token === token else { return }
        cancelActiveTurn()
    }

    private func cancelActiveTurn() {
        cancelConsents()
        continuation?.finish(throwing: CancellationError())
        continuation = nil
        process?.terminate()
        outputBuffer.removeAll(keepingCapacity: false)
        errorBuffer.removeAll(keepingCapacity: false)
        removePrivateFiles()
    }

    /// Both are the turn's own: a prompt nobody else may read, and a configuration full of secrets.
    private func removePrivateFiles() {
        if let promptFileURL {
            try? FileManager.default.removeItem(at: promptFileURL)
        }
        promptFileURL = nil
        if let mcpConfigURL {
            try? FileManager.default.removeItem(at: mcpConfigURL)
        }
        mcpConfigURL = nil
    }

    private func deleteTurnSession() {
        guard let sessionID = turnSessionID else { return }
        turnSessionID = nil
        switch kind {
        case .openCode, .grok:
            guard let executable = activeExecutable else { return }
            let arguments =
                kind == .grok
                ? ["sessions", "delete", sessionID] : ["session", "delete", sessionID, "--pure"]
            let workspace = workspace
            let environment = environment(for: executable)
            Task.detached {
                Self.deleteCLISession(
                    arguments: arguments, executable: executable, workspace: workspace,
                    environment: environment)
            }
        case .cursor:
            let root = Self.cursorChatsRoot()
            Task.detached { Self.deleteCursorChat(sessionID, root: root) }
        case .claude, .codex:
            break
        }
    }

    nonisolated private static func deleteCLISession(
        arguments: [String], executable: URL, workspace: URL, environment: [String: String]
    ) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workspace
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    /// The CLI has no delete-chat; chats live under `~/.cursor/chats/<workspace>/<id>`.
    nonisolated private static func deleteCursorChat(_ sessionID: String, root: URL) {
        let fm = FileManager.default
        guard let workspaces = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        else { return }
        for workspace in workspaces {
            try? fm.removeItem(
                at: workspace.appending(path: sessionID, directoryHint: .isDirectory))
        }
    }

    private static func cursorChatsRoot() -> URL {
        if let override = ProcessInfo.processInfo.environment["TC_CURSOR_CHATS_ROOT"],
            !override.isEmpty
        {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(
            path: ".cursor/chats", directoryHint: .isDirectory)
    }

    private func cleanup() {
        cancelConsents()
        process?.terminationHandler = nil
        (process?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        (process?.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        process = nil
        token = nil
        continuation = nil
        outputBuffer.removeAll(keepingCapacity: false)
        errorBuffer.removeAll(keepingCapacity: false)
        turnSessionID = nil
        removePrivateFiles()
        activeExecutable = nil
        activeServers = []
        try? input?.close()
        input = nil
    }
}
