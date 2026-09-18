import Foundation

struct InstalledCLIProvider: AIProvider {
    private let runner: InstalledCLITurnRunner

    @MainActor
    init(
        kind: InstalledAIKind, executable: URL?, model: String, effort: String?, workspace: URL
    ) {
        runner = InstalledCLITurnRunner(
            kind: kind, executable: executable, model: model, effort: effort,
            workspace: workspace)
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
    private static let openCodeConfiguration = """
        {"permission":"deny","share":"disabled","agent":{"build":{"permission":"deny"},\
        "plan":{"permission":"deny"}}}
        """

    private static let claudeManagedMCPConfig =
        "/Library/Application Support/ClaudeCode/managed-mcp.json"

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

    private var token: TurnToken?
    private var process: Process?
    private var continuation: AIProviderStream.Continuation?
    private var outputBuffer = Data()
    private var errorBuffer = Data()
    private var turnSessionID: String?
    private var promptFileURL: URL?
    private var activeExecutable: URL?

    init(
        kind: InstalledAIKind, executable: URL?, model: String, effort: String?, workspace: URL
    ) {
        self.kind = kind
        configuredExecutable = executable
        self.model = model
        self.effort = effort
        self.workspace = workspace
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
        guard let prompt = prompt(for: request) else {
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
        process.arguments = arguments(promptFile: grokPrompt)
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
            continuation.finish(
                throwing: AIProviderError.responseFailed(
                    kind.title + " could not start: " + error.localizedDescription))
            return
        }
        promptFileURL = grokPrompt
        self.process = process
        activeExecutable = executable
        self.token = token
        self.continuation = continuation
        guard kind != .grok else { return }
        // A prompt past the pipe buffer blocks until the child drains it, so never on the main actor.
        let input = stdin.fileHandleForWriting
        Task.detached {
            try? input.write(contentsOf: Data(prompt.utf8))
            try? input.close()
        }
    }

    nonisolated private static func writePromptFile(_ prompt: String, to url: URL) async throws {
        try await Task.detached {
            try Data(prompt.utf8).write(to: url)
        }.value
    }

    private func arguments(promptFile: URL? = nil) -> [String] {
        switch kind {
        case .claude:
            var result = [
                "-p",
                "--model", model,
                "--input-format", "text",
                "--output-format", "stream-json",
                "--verbose",
                "--include-partial-messages",
                "--no-session-persistence",
                "--disable-slash-commands",
                "--tools", "",
                "--disallowedTools", "*",
                // `--bare` is not among these: it refuses the OAuth sign-in this whole route reuses.
                "--no-chrome",
                "--max-turns", "1",
                "--system-prompt", Self.safetyInstructions
            ]
            // The CLI rejects both flags while an admin's managed MCP policy is installed.
            if !FileManager.default.fileExists(atPath: Self.claudeManagedMCPConfig) {
                result += ["--strict-mcp-config", "--mcp-config", #"{"mcpServers":{}}"#]
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

    private func prompt(for request: AIRequest) -> String? {
        guard
            request.messages.contains(where: {
                $0.role == .user
                    && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
        else { return nil }
        var sections = [Self.safetyInstructions]
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
            apply(InstalledAIStreamDecoder.decode(Data(line), kind: kind))
        }
        if outputBuffer.count > Self.maximumPartialLineBytes {
            fail(kind.title + " returned an oversized response.")
        }
    }

    private func apply(_ frame: InstalledAIStreamFrame) {
        if let sessionID = frame.sessionID { turnSessionID = sessionID }
        for event in frame.events { continuation?.yield(event) }
        if let error = frame.error {
            fail(error)
        } else if frame.completed {
            continuation?.yield(.finished)
            continuation?.finish()
            continuation = nil
        }
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
        continuation?.finish(throwing: CancellationError())
        continuation = nil
        process?.terminate()
        outputBuffer.removeAll(keepingCapacity: false)
        errorBuffer.removeAll(keepingCapacity: false)
        removePromptFile()
    }

    private func removePromptFile() {
        if let promptFileURL {
            try? FileManager.default.removeItem(at: promptFileURL)
        }
        promptFileURL = nil
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
        process?.terminationHandler = nil
        (process?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        (process?.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        process = nil
        token = nil
        continuation = nil
        outputBuffer.removeAll(keepingCapacity: false)
        errorBuffer.removeAll(keepingCapacity: false)
        turnSessionID = nil
        removePromptFile()
        activeExecutable = nil
    }
}
