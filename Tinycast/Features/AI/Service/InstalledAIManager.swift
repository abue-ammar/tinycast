import Foundation
import Observation

@MainActor
@Observable
final class InstalledAIManager {
    private(set) var statuses = Dictionary(
        uniqueKeysWithValues: InstalledAIKind.allCases.map { ($0, InstalledAIStatus()) })

    @ObservationIgnored private let workspace: URL
    @ObservationIgnored private var refreshTasks: [InstalledAIKind: Task<Void, Never>] = [:]

    /// An admin's MCP policy makes the Claude CLI reject both MCP flags, so the route passes
    /// neither and says so. A harness points this at a file it owns to exercise that branch.
    nonisolated static var hasManagedMCPPolicy: Bool {
        let path =
            ProcessInfo.processInfo.environment["TC_CLAUDE_MANAGED_MCP"]
            ?? "/Library/Application Support/ClaudeCode/managed-mcp.json"
        return FileManager.default.fileExists(atPath: path)
    }

    init(supportDirectory: URL = AppPaths.applicationSupport()) {
        workspace = supportDirectory.appending(
            path: "InstalledAI/Workspace", directoryHint: .isDirectory)
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
            return (
                kind,
                InstalledAIStatus(
                    phase: auth.status == 0 && loggedIn ? .ready : .signInRequired,
                    version: version, executable: executable,
                    models: loggedIn ? InstalledAIModel.claude : [])
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
            return (
                kind,
                InstalledAIStatus(
                    phase: models.status == 0 && !catalog.isEmpty ? .ready : .signInRequired,
                    version: version, executable: executable, models: catalog)
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
