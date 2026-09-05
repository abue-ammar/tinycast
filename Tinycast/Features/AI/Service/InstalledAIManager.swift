import Foundation
import Observation

@MainActor
@Observable
final class InstalledAIManager {
    private(set) var statuses = Dictionary(
        uniqueKeysWithValues: InstalledAIKind.allCases.map { ($0, InstalledAIStatus()) })

    @ObservationIgnored private let workspace: URL
    @ObservationIgnored private var refreshTasks: [InstalledAIKind: Task<Void, Never>] = [:]

    init(supportDirectory: URL = AppPaths.applicationSupport()) {
        workspace = supportDirectory.appending(
            path: "InstalledAI/Workspace", directoryHint: .isDirectory)
    }

    func status(for kind: InstalledAIKind) -> InstalledAIStatus {
        statuses[kind] ?? InstalledAIStatus()
    }

    @discardableResult
    func refresh(enabledKinds: Set<InstalledAIKind> = [.claude, .openCode]) -> Task<Void, Never> {
        var tasks: [Task<Void, Never>] = []
        for kind in [InstalledAIKind.claude, .openCode] {
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
        for kind in [InstalledAIKind.claude, .openCode] {
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

    func provider(kind: InstalledAIKind, model: String, effort: String?) throws -> any AIProvider {
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
            workspace: workspace)
    }

    nonisolated private static func probe(
        _ kind: InstalledAIKind, workspace: URL
    ) async -> (InstalledAIKind, InstalledAIStatus) {
        guard let executable = await InstalledAIExecutableLocator.locate(kind) else {
            return (kind, InstalledAIStatus(phase: .notInstalled))
        }
        let versionResult = await InstalledAIProbe.run(
            executable: executable, arguments: ["--version"], workspace: workspace)
        guard versionResult.status == 0 else {
            return (
                kind,
                InstalledAIStatus(
                    phase: .failed("The installed command could not run."),
                    executable: executable))
        }
        let version = InstalledAIProbe.version(in: versionResult.output)
        switch kind {
        case .claude:
            let auth = await InstalledAIProbe.run(
                executable: executable, arguments: ["auth", "status", "--json"],
                workspace: workspace)
            let loggedIn = InstalledAIProbe.loggedIn(toClaude: auth.output)
            return (
                kind,
                InstalledAIStatus(
                    phase: auth.status == 0 && loggedIn ? .ready : .signInRequired,
                    version: version, executable: executable,
                    models: loggedIn ? InstalledAIModel.claude : []))
        case .openCode:
            let models = await InstalledAIProbe.run(
                executable: executable, arguments: ["models", "--pure", "--verbose"],
                workspace: workspace)
            let catalog = InstalledAIModel.openCodeCatalog(models.output)
            return (
                kind,
                InstalledAIStatus(
                    phase: models.status == 0 && !catalog.isEmpty ? .ready : .signInRequired,
                    version: version, executable: executable, models: catalog))
        case .codex:
            return (kind, InstalledAIStatus(phase: .idle))
        }
    }
}

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
        executable: URL, arguments: [String], workspace: URL
    ) async -> Result {
        let handle = ProcessHandle()
        return await withTaskCancellationHandler(operation: {
            try? FileManager.default.createDirectory(
                at: workspace, withIntermediateDirectories: true)
            let process = Process()
            let output = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = workspace
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
            if data.count == Self.maximumOutputBytes, process.isRunning { process.terminate() }
            process.waitUntilExit()
            watchdog.cancel()
            return Result(
                status: process.terminationStatus,
                output: String(bytes: data.prefix(2 * 1_048_576), encoding: .utf8) ?? "")
        }, onCancel: {
            handle.cancel()
        })
    }

    nonisolated static func version(in output: String) -> String? {
        output.firstMatch(of: #/\d+\.\d+(?:\.\d+)?/#).map { String($0.output) }
    }

    nonisolated static func loggedIn(toClaude output: String) -> Bool {
        guard let data = output.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return object["loggedIn"] as? Bool == true
            || object["authenticated"] as? Bool == true
            || object["isAuthenticated"] as? Bool == true
    }

}
