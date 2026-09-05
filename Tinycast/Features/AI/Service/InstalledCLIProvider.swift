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
    private var openCodeSessionID: String?
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
            resolvedExecutable = await InstalledAIExecutableLocator.locate(kind)
        }
        guard let executable = resolvedExecutable else {
            continuation.finish(
                throwing: AIProviderError.unavailable(
                    "Install " + kind.title + " before using this model."))
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
        process.arguments = arguments
        process.currentDirectoryURL = workspace
        process.environment = environment(for: executable)
        process.standardInput = stdin
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
        process.terminationHandler = { [self] process in
            let status = process.terminationStatus
            Task { @MainActor in self.didExit(status: status, token: token) }
        }
        do {
            try process.run()
            self.process = process
            activeExecutable = executable
            self.token = token
            self.continuation = continuation
            try stdin.fileHandleForWriting.write(contentsOf: Data(prompt.utf8))
            try stdin.fileHandleForWriting.close()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            process.terminationHandler = nil
            continuation.finish(
                throwing: AIProviderError.responseFailed(
                    kind.title + " could not start: " + error.localizedDescription))
            cleanup()
        }
    }

    private var arguments: [String] {
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
                "--bare",
                "--disable-slash-commands",
                "--tools", "",
                "--disallowedTools", "*",
                "--strict-mcp-config",
                "--mcp-config", "{}",
                "--no-chrome",
                "--max-turns", "1",
                "--system-prompt", Self.safetyInstructions
            ]
            if let effort { result += ["--effort", effort] }
            return result
        case .openCode:
            var result = [
                "run", "--pure", "--format", "json", "--model", model,
                "--dir", workspace.path, "--title", "Tinycast"
            ]
            if let effort { result += ["--variant", effort] }
            return result
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
        case .codex:
            break
        }
        return result
    }

    private func prompt(for request: AIRequest) -> String? {
        guard request.messages.contains(where: {
            $0.role == .user
                && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else { return nil }
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
            outputBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            apply(InstalledAIStreamDecoder.decode(Data(line), kind: kind))
        }
        guard outputBuffer.count <= 8 * 1_048_576 else {
            fail(kind.title + " returned an oversized response.")
            return
        }
    }

    private func apply(_ frame: InstalledAIStreamFrame) {
        if let sessionID = frame.sessionID { openCodeSessionID = sessionID }
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
                    of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = kind.title + " exited with status " + String(status) + "."
            fail(detail.isEmpty ? fallback : detail)
        }
        deleteOpenCodeSession()
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
    }

    private func deleteOpenCodeSession() {
        guard kind == .openCode, let sessionID = openCodeSessionID,
            let executable = activeExecutable
        else { return }
        let workspace = workspace
        let environment = environment(for: executable)
        Task.detached {
            let process = Process()
            process.executableURL = executable
            process.arguments = ["session", "delete", sessionID, "--pure"]
            process.currentDirectoryURL = workspace
            process.environment = environment
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
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
        openCodeSessionID = nil
        activeExecutable = nil
    }
}
