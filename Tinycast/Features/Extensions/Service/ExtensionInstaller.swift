import Foundation

/// Turns a listing into an installed extension.
///
/// Two paths, because the two registry kinds hand back different things:
///
/// - **Prebuilt** (Raycast's store): download a zip, expand it, install it. No toolchain at all.
/// - **Source** (a GitHub registry): fetch only that extension's folder, install its dependencies
///   with the chosen package manager, run its `build` script — which is `ray build` — and install
///   what that produced.
///
/// Everything happens in a temporary directory that is removed whichever way this ends, so a failed
/// install leaves nothing behind and a half-built extension is never visible to the scanner.
struct ExtensionInstaller: Sendable {
    /// A step worth showing: an install can take minutes on the source path, and silence for that
    /// long reads as a hang.
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

    /// Long enough for a cold dependency install on a slow connection, short enough that a wedged
    /// child process doesn't hang the pane forever.
    private static let commandTimeout: TimeInterval = 300

    let client: ExtensionStoreClient
    let packageManager: ExtensionPackageManager

    init(client: ExtensionStoreClient = ExtensionStoreClient(), packageManager: ExtensionPackageManager) {
        self.client = client
        self.packageManager = packageManager
    }

    /// Installs, and copies into place before the workspace goes: the prepared directory only
    /// exists inside it, so handing the path back to a caller would hand back a deleted one.
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

    /// The store's zip wraps the extension in a directory named after it; a folder built locally may
    /// not. Accept either rather than depending on which.
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

        // `ray` directly, never the manifest's `build` script: that script is `ray build`, whose
        // default environment is `dev`, and dev installs into the local Raycast rather than emitting.
        // `-o` must not be the source — ray clears its output directory, which took `assets/` with it.
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
        // Node's own directory first: `ray build` is spawned by the package manager, which finds it
        // on PATH, and a Node installed through a version manager is nowhere near the defaults.
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
