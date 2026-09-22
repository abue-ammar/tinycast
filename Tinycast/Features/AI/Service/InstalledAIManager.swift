import Foundation
import Observation

@MainActor
@Observable
final class InstalledAIManager {
    private(set) var statuses = Dictionary(
        uniqueKeysWithValues: InstalledAIKind.allCases.map { ($0, InstalledAIStatus()) })

    @ObservationIgnored private let workspace: URL
    @ObservationIgnored private var refreshTasks: [InstalledAIKind: Task<Void, Never>] = [:]

    /// An admin's MCP policy makes Claude reject both MCP flags; a harness points this elsewhere.
    nonisolated static var hasManagedMCPPolicy: Bool {
        let path =
            ProcessInfo.processInfo.environment["TC_CLAUDE_MANAGED_MCP"]
            ?? "/Library/Application Support/ClaudeCode/managed-mcp.json"
        return FileManager.default.fileExists(atPath: path)
    }

    /// No MCP server at all, for a Claude process that is handed none: a plain turn or a probe.
    nonisolated static var claudeWithoutMCPArguments: [String] {
        hasManagedMCPPolicy ? [] : ["--strict-mcp-config", "--mcp-config", #"{"mcpServers":{}}"#]
    }

    /// A control request answered without a prompt, so the CLI replies without calling a model.
    nonisolated private static var claudeControlArguments: [String] {
        [
            "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
            "--no-session-persistence"
        ] + claudeWithoutMCPArguments
    }

    init(supportDirectory: URL = AppPaths.applicationSupport()) {
        workspace = supportDirectory.appending(
            path: "InstalledAI/Workspace", directoryHint: .isDirectory)
        let workspace = workspace
        let launch = Date()
        Task.detached(priority: .utility) {
            Self.removeStaleTurnFiles(in: workspace, olderThan: launch)
        }
    }

    /// A turn deletes its own files as it ends, so any older than this launch outlived a crash.
    nonisolated private static func removeStaleTurnFiles(
        in workspace: URL, olderThan launch: Date
    ) {
        let fileManager = FileManager.default
        guard
            let files = try? fileManager.contentsOfDirectory(
                at: workspace, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return }
        for file in files {
            let name = file.lastPathComponent
            guard
                (name.hasPrefix("tinycast-mcp-") && name.hasSuffix(".json"))
                    || (name.hasPrefix("tinycast-prompt-") && name.hasSuffix(".txt")),
                let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate,
                modified < launch
            else { continue }
            try? fileManager.removeItem(at: file)
        }
    }

    func status(for kind: InstalledAIKind) -> InstalledAIStatus {
        statuses[kind] ?? InstalledAIStatus()
    }

    func models(for source: AIModelSource) -> [InstalledAIModel] {
        source.installedKind.map { status(for: $0).models } ?? []
    }

    @discardableResult
    func refresh(
        enabledKinds: Set<InstalledAIKind> = Set(InstalledAIKind.managedCLIKinds)
    ) -> Task<Void, Never> {
        var tasks: [Task<Void, Never>] = []
        for kind in InstalledAIKind.managedCLIKinds {
            if enabledKinds.contains(kind) {
                tasks.append(refresh(kind: kind))
            } else {
                stop(kind: kind)
            }
        }
        return Task { for task in tasks { await task.value } }
    }

    @discardableResult
    func refresh(kind: InstalledAIKind) -> Task<Void, Never> {
        guard kind != .codex else { return Task {} }
        refreshTasks[kind]?.cancel()
        statuses[kind] = InstalledAIStatus(phase: .checking)
        let workspace = workspace
        let task = Task { [weak self] in
            guard let self else { return }
            let result = await Self.probe(kind, workspace: workspace)
            guard !Task.isCancelled else { return }
            self.statuses[result.0] = result.1
        }
        refreshTasks[kind] = task
        return task
    }

    func ensure(enabledKinds: Set<InstalledAIKind>) -> Task<Void, Never> {
        var tasks: [Task<Void, Never>] = []
        for kind in InstalledAIKind.managedCLIKinds {
            guard enabledKinds.contains(kind) else {
                stop(kind: kind)
                continue
            }
            switch status(for: kind).phase {
            case .idle:
                tasks.append(refresh(kind: kind))
            case .checking:
                if let task = refreshTasks[kind] { tasks.append(task) }
            case .ready, .signInRequired, .notInstalled, .failed:
                break
            }
        }
        return Task { for task in tasks { await task.value } }
    }

    func stop() {
        for task in refreshTasks.values { task.cancel() }
        refreshTasks.removeAll()
        statuses = Dictionary(
            uniqueKeysWithValues: InstalledAIKind.allCases.map { ($0, InstalledAIStatus()) })
    }

    private func stop(kind: InstalledAIKind) {
        refreshTasks[kind]?.cancel()
        refreshTasks[kind] = nil
        statuses[kind] = InstalledAIStatus()
    }

    /// Claude Code names its own sessions; asking it here costs one small request, not a turn.
    func claudeTitle(for description: String) async -> String? {
        guard status(for: .claude).isReady, let executable = status(for: .claude).executable,
            let request = InstalledAIModel.claudeTitleRequest(description)
        else { return nil }
        let output = await InstalledAIProbe.request(
            executable: executable, arguments: Self.claudeControlArguments,
            workspace: workspace, input: Data(request.utf8),
            until: { output in
                // A whole line: the ID arrives before the title, so a chunk may split between them.
                output.split(separator: "\n", omittingEmptySubsequences: false).dropLast()
                    .contains { $0.contains(InstalledAIModel.claudeTitleRequestID) }
            })
        return InstalledAIModel.claudeTitle(output).flatMap(ChatTitle.sanitize)
    }

    func provider(
        kind: InstalledAIKind, model: String, effort: String?,
        toolServers: AIToolServerSession? = nil
    ) throws -> any AIProvider {
        guard kind != .codex else {
            throw AIProviderError.unavailable("Codex is handled by its app-server connection.")
        }
        let status = status(for: kind)
        guard status.phase != .notInstalled else {
            throw AIProviderError.unavailable("Install " + kind.title + " before using this model.")
        }
        guard status.phase != .signInRequired else {
            throw AIProviderError.unavailable("Sign in with `" + kind.signInCommand + "` first.")
        }
        return InstalledCLIProvider(
            kind: kind, executable: status.executable, model: model, effort: effort,
            workspace: workspace, toolServers: toolServers)
    }

    nonisolated private static func probe(
        _ kind: InstalledAIKind, workspace: URL
    ) async -> (InstalledAIKind, InstalledAIStatus) {
        guard
            let executable = await ExecutableLocator.locate(
                kind.command, extraHomePaths: kind.extraExecutablePaths)
        else {
            return (kind, InstalledAIStatus(phase: .notInstalled))
        }
        let versionResult = await InstalledAIProbe.run(
            executable: executable, arguments: ["--version"], workspace: workspace)
        guard versionResult.status == 0 else {
            return (
                kind,
                InstalledAIStatus(
                    phase: .failed("The installed command could not run."),
                    executable: executable)
            )
        }
        let version = InstalledAIProbe.version(in: versionResult.output)
        switch kind {
        case .claude:
            let auth = await InstalledAIProbe.run(
                executable: executable, arguments: ["auth", "status", "--json"],
                workspace: workspace)
            let loggedIn = InstalledAIProbe.loggedIn(inStatusJSON: auth.output)
            guard auth.status == 0, loggedIn else {
                return (
                    kind,
                    InstalledAIStatus(
                        phase: .signInRequired, version: version, executable: executable)
                )
            }
            // No prompt follows the request, so the CLI answers and exits without calling a model.
            let catalog = await InstalledAIProbe.run(
                executable: executable, arguments: claudeControlArguments, workspace: workspace,
                input: Data(InstalledAIModel.claudeInitializeRequest.utf8),
                // The reader's SessionStart hooks run before the CLI answers, however slow they are.
                timeout: .seconds(30))
            let models = InstalledAIModel.claudeCatalog(catalog.output)
            return (
                kind,
                InstalledAIStatus(
                    phase: models.isEmpty
                        ? .failed("Claude listed no models. Update Claude Code, then Check Again.")
                        : .ready,
                    version: version, executable: executable, models: models)
            )
        case .openCode:
            let models = await InstalledAIProbe.run(
                executable: executable, arguments: ["models", "--pure", "--verbose"],
                workspace: workspace)
            let catalog = InstalledAIModel.openCodeCatalog(models.output)
            return (
                kind,
                InstalledAIStatus(
                    phase: models.status == 0 && !catalog.isEmpty ? .ready : .signInRequired,
                    version: version, executable: executable, models: catalog)
            )
        case .grok:
            let models = await InstalledAIProbe.run(
                executable: executable, arguments: ["models"], workspace: workspace)
            let catalog = InstalledAIModel.grokCatalog(models.output)
            let signedIn = models.status == 0 && InstalledAIModel.grokSignedIn(models.output)
            return (
                kind,
                InstalledAIStatus(
                    phase: signedIn && !catalog.isEmpty ? .ready : .signInRequired,
                    version: version, executable: executable,
                    models: signedIn ? catalog : [])
            )
        case .cursor:
            let auth = await InstalledAIProbe.run(
                executable: executable, arguments: ["status", "--format", "json"],
                workspace: workspace)
            let loggedIn = InstalledAIProbe.loggedIn(inStatusJSON: auth.output)
            guard auth.status == 0, loggedIn else {
                return (
                    kind,
                    InstalledAIStatus(
                        phase: .signInRequired, version: version, executable: executable)
                )
            }
            let models = await InstalledAIProbe.run(
                executable: executable, arguments: ["--list-models"], workspace: workspace)
            let catalog = InstalledAIModel.cursorCatalog(models.output)
            return (
                kind,
                InstalledAIStatus(
                    phase: models.status == 0 && !catalog.isEmpty
                        ? .ready
                        : .failed(
                            "Cursor returned no models."),
                    version: version, executable: executable, models: catalog)
            )
        case .codex:
            return (kind, InstalledAIStatus(phase: .idle))
        }
    }
}
