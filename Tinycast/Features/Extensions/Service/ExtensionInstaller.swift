import Foundation

/// Turns a listing into an installed extension, in a workspace removed whichever way this ends.
struct ExtensionInstaller: Sendable {
    /// An install can take minutes from source, and silence for that long reads as a hang.
    enum Progress: Sendable, Equatable {
        case downloading
        case installingDependencies(manager: String)
        case building
        case installing

        var message: String {
            switch self {
            case .downloading: return "Downloading…"
            case .installingDependencies(let manager): return "Installing dependencies with \(manager)…"
            case .building: return "Building…"
            case .installing: return "Installing…"
            }
        }
    }

    /// Long enough for a cold install on a slow line, short enough that a wedged child can't hang.
    private static let commandTimeout: TimeInterval = 300

    let client: ExtensionStoreClient
    let packageManager: ExtensionPackageManager

    init(client: ExtensionStoreClient = ExtensionStoreClient(), packageManager: ExtensionPackageManager) {
        self.client = client
        self.packageManager = packageManager
    }

    /// Copies into place before the workspace goes, which is why it hands back the install, not a path.
    @discardableResult
    func install(
        _ listing: ExtensionListing, onProgress: @Sendable @escaping (Progress) -> Void
    ) async throws -> InstalledExtension {
        let workspace = ExtensionCleanup.workspace(in: FileManager.default.temporaryDirectory)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let prepared: URL
        switch listing.source {
        case .prebuiltZip(let url):
            onProgress(.downloading)
            prepared = try await preparePrebuilt(from: url, in: workspace)
        case .githubFolder(let owner, let repository, let path, let ref):
            onProgress(.downloading)
            let source = workspace.appendingPathComponent("source", isDirectory: true)
            try await client.downloadFolder(
                owner: owner, repository: repository, path: path, ref: ref, to: source)
            prepared = try await build(
                at: source, into: workspace.appendingPathComponent("build", isDirectory: true),
                onProgress: onProgress)
        }
        onProgress(.installing)
        return try ExtensionCatalog.install(from: prepared)
    }

    // MARK: - Prebuilt

    private func preparePrebuilt(from url: URL, in workspace: URL) async throws -> URL {
        let data = try await client.download(url)
        let archive = workspace.appendingPathComponent("extension.zip")
        try data.write(to: archive, options: .atomic)

        let expanded = workspace.appendingPathComponent("expanded", isDirectory: true)
        try FileManager.default.createDirectory(at: expanded, withIntermediateDirectories: true)
        // `ditto` ships with macOS and handles the zips the store serves; Foundation has no unzip.
        let result = try await run(
            URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-x", "-k", archive.path, expanded.path], in: workspace)
        guard result.status == 0 else {
            throw ExtensionStoreError.downloadFailed(result.trimmedOutput)
        }
        return try locateManifestRoot(in: expanded)
    }

    /// The store's zip wraps the extension in a directory; a local build may not. Accept either.
    private func locateManifestRoot(in directory: URL) throws -> URL {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directory.appendingPathComponent("package.json").path) {
            return directory
        }
        let children =
            (try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])) ?? []
        for child in children
        where fileManager.fileExists(atPath: child.appendingPathComponent("package.json").path) {
            return child
        }
        throw ExtensionStoreError.notAnExtension
    }

    // MARK: - Source

    /// Returns the directory to install from: `output` when `ray` produced it, else `source`.
    private func build(
        at source: URL, into output: URL, onProgress: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        guard let resolved = packageManager.resolve() else {
            throw ExtensionStoreError.noPackageManager
        }
        guard let node = ExtensionPackageManager.nodeURL() else {
            throw ExtensionStoreError.noNode
        }

        onProgress(.installingDependencies(manager: resolved.manager.title))
        let install = try await run(
            resolved.url, arguments: resolved.manager.installArguments, in: source, node: node)
        guard install.status == 0 else {
            throw ExtensionStoreError.buildFailed(install.trimmedOutput)
        }

        onProgress(.building)
        let ray = source.appendingPathComponent("node_modules/.bin/ray")
        guard FileManager.default.isExecutableFile(atPath: ray.path) else {
            // Not a Raycast build. Its own script is the only contract there is, and it emits in place.
            let build = try await run(
                resolved.url, arguments: resolved.manager.buildArguments, in: source, node: node)
            guard build.status == 0 else {
                throw ExtensionStoreError.buildFailed(build.trimmedOutput)
            }
            return try validated(source)
        }

        // `ray` directly, `-e dist`, `-o` never the source: dev installs into Raycast, and `-o` clears.
        let build = try await run(
            ray, arguments: ["build", "-e", "dist", "-o", output.path, "--non-interactive"],
            in: source, node: node)
        guard build.status == 0 else {
            throw ExtensionStoreError.buildFailed(build.trimmedOutput)
        }
        return try validated(output)
    }

    private func validated(_ directory: URL) throws -> URL {
        guard
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("package.json").path)
        else { throw ExtensionStoreError.notAnExtension }
        return directory
    }

    // MARK: - Running a child process

    private struct CommandResult {
        let status: Int32
        let output: String

        /// The tail, which is where a package manager puts the actual error.
        var trimmedOutput: String {
            let lines = output.split(separator: "\n").suffix(6)
            let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? "no output" : text
        }
    }

    /// Runs a tool with a PATH built for a GUI app, which inherits none of a login shell's.
    private func run(
        _ executable: URL, arguments: [String], in directory: URL, node: URL? = nil
    ) async throws -> CommandResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory

        var environment = ProcessInfo.processInfo.environment
        var searchPath = ExtensionPackageManager.searchPaths
        // Node first: the package manager spawns `ray` off PATH, and a version manager hides Node.
        if let node { searchPath.insert(node.deletingLastPathComponent().path, at: 0) }
        environment["PATH"] = searchPath.joined(separator: ":")
        // Keeps npm from writing progress bars into the output we surface on failure.
        environment["CI"] = "1"
        environment["NO_COLOR"] = "1"
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        return try await withCheckedThrowingContinuation { continuation in
            // One resume, whichever of termination and timeout arrives first.
            let state = ResumeGuard()
            process.terminationHandler = { finished in
                let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
                guard state.claim() else { return }
                continuation.resume(
                    returning: CommandResult(
                        status: finished.terminationStatus,
                        output: String(decoding: data, as: UTF8.self)))
            }
            do {
                try process.run()
            } catch {
                guard state.claim() else { return }
                continuation.resume(throwing: error)
                return
            }
            Task {
                try? await Task.sleep(for: .seconds(Self.commandTimeout))
                guard process.isRunning else { return }
                process.terminate()
                guard state.claim() else { return }
                continuation.resume(
                    returning: CommandResult(status: -1, output: "timed out after 5 minutes"))
            }
        }
    }
}

/// Lets exactly one of two racing paths resume a continuation.
private final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
