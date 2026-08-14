import Foundation

/// An installed extension: its manifest plus where it lives on disk.
struct InstalledExtension: Sendable, Hashable, Identifiable {
    let manifest: ExtensionManifest
    let directory: URL

    var id: String { manifest.name }
    var title: String { manifest.title }

    /// The manifest icon resolved to a file — Raycast bundles put assets in `assets/`, but a few
    /// reference a path relative to the extension root.
    var iconPath: String? {
        guard let icon = manifest.icon else { return nil }
        let candidates = [
            directory.appendingPathComponent("assets").appendingPathComponent(icon),
            directory.appendingPathComponent(icon)
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }?.path
    }

    var assetsPath: String { directory.appendingPathComponent("assets").path }

    /// The prebuilt CommonJS bundle for a command, or nil when the install is incomplete.
    func bundleURL(for command: ExtensionCommand) -> URL? {
        let url = directory.appendingPathComponent("\(command.name).js")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func command(named name: String) -> ExtensionCommand? {
        manifest.commands.first { $0.name == name }
    }
}

/// A specific command of a specific extension — what the launcher activates.
struct ExtensionCommandRef: Sendable, Hashable {
    let extensionName: String
    let commandName: String

    /// The `AppEntry.id` an extension command is surfaced under.
    var entryID: String { "extension:\(extensionName)/\(commandName)" }

    init(extensionName: String, commandName: String) {
        self.extensionName = extensionName
        self.commandName = commandName
    }

    init?(entryID: String) {
        guard entryID.hasPrefix("extension:") else { return nil }
        let body = entryID.dropFirst("extension:".count)
        guard let slash = body.lastIndex(of: "/") else { return nil }
        extensionName = String(body[body.startIndex..<slash])
        commandName = String(body[body.index(after: slash)...])
    }
}

/// Finds installed extensions on disk and installs new ones.
///
/// Tinycast stores extensions the way Raycast does — a directory holding `package.json`, `assets/` and
/// one prebuilt `<command>.js` per command, with `react` / `@raycast/api` / Node builtins left external.
/// That is deliberate: it is the format Raycast's own build produces, so an extension already built by
/// Raycast (or by `ray build`) can be imported as-is and no bundler is needed at runtime.
enum ExtensionCatalog {
    /// `~/Library/Application Support/<bundle id>/extensions`. Keyed by bundle id, so a Debug build
    /// never shares installs with a release channel.
    static func extensionsDirectory() -> URL {
        supportDirectory().appendingPathComponent("extensions", isDirectory: true)
    }

    static func storageDirectory() -> URL {
        supportDirectory().appendingPathComponent("extension-data", isDirectory: true)
    }

    /// Per-extension `environment.supportPath` — an extension's own scratch directory.
    static func supportPath(for name: String) -> URL {
        supportRoot().appendingPathComponent(safeName(name), isDirectory: true)
    }

    static func supportRoot() -> URL {
        supportDirectory().appendingPathComponent("extension-support", isDirectory: true)
    }

    /// Extension names are npm-style (`spotify-player`, `@scope/name`); flatten to one path segment.
    /// Shared, because a second copy that drifts orphans every file the first one wrote.
    static func safeName(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: "@", with: "")
    }

    private static func supportDirectory() -> URL {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
        let bundleID = Bundle.main.bundleIdentifier ?? "com.tinycast.app"
        return base.appendingPathComponent(bundleID, isDirectory: true)
    }

    /// Every root a locally installed Raycast keeps built bundles in. `raycast-x` is Raycast Beta v2;
    /// both can exist, and a stable install leaves an empty `raycast` behind after switching.
    static func raycastExtensionRoots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ["raycast", "raycast-x"].map {
            home.appendingPathComponent(".config/\($0)/extensions", isDirectory: true)
        }
    }

    /// The root worth importing from — the first that actually holds something, so an empty directory
    /// left by the other channel never reads as "Raycast isn't installed".
    static func raycastExtensionsDirectory() -> URL? {
        raycastExtensionRoots().first { root in
            let entries = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            return !(entries ?? []).isEmpty
        }
    }

    /// Scan the install directory. Unreadable or half-written directories are skipped rather than
    /// failing the whole scan.
    nonisolated static func scan() -> [InstalledExtension] {
        let root = extensionsDirectory()
        let entries =
            (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])) ?? []
        return
            entries
            .compactMap { directory -> InstalledExtension? in
                guard let manifest = try? ExtensionManifest.load(directory: directory),
                    manifest.supportsMacOS
                else { return nil }
                return InstalledExtension(manifest: manifest, directory: directory)
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: - Install

    enum InstallError: LocalizedError {
        case notAnExtension(URL)
        case noBuiltCommands(String)
        case wrongPlatform(String)
        case copyFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAnExtension(let url):
                return
                    "\(url.lastPathComponent) doesn't contain a Raycast extension (no package.json with commands)."
            case .noBuiltCommands(let name):
                return
                    "\(name) has no built command bundles. Tinycast installs prebuilt extensions — run `ray build` in the extension folder first, or import one from an installed Raycast."
            case .wrongPlatform(let name):
                return "\(name) doesn't support macOS."
            case .copyFailed(let reason):
                return "Couldn't install the extension: \(reason)"
            }
        }
    }

    /// Copy a prebuilt extension directory into the install root. Only the manifest, the built command
    /// bundles and `assets/` are copied — never `node_modules` or the multi-MB `.js.map` files Raycast
    /// writes next to each bundle.
    @discardableResult
    static func install(from source: URL) throws -> InstalledExtension {
        guard let manifest = try? ExtensionManifest.load(directory: source) else {
            throw InstallError.notAnExtension(source)
        }
        guard manifest.supportsMacOS else { throw InstallError.wrongPlatform(manifest.title) }

        let fm = FileManager.default
        let built = manifest.commands.filter {
            fm.fileExists(atPath: source.appendingPathComponent("\($0.name).js").path)
        }
        guard !built.isEmpty else { throw InstallError.noBuiltCommands(manifest.title) }

        let destination = extensionsDirectory().appendingPathComponent(
            manifest.name.replacingOccurrences(of: "/", with: "-"), isDirectory: true)
        do {
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            try fm.copyItem(
                at: source.appendingPathComponent("package.json"),
                to: destination.appendingPathComponent("package.json"))
            for command in built {
                let file = "\(command.name).js"
                try fm.copyItem(
                    at: source.appendingPathComponent(file),
                    to: destination.appendingPathComponent(file))
            }
            let assets = source.appendingPathComponent("assets")
            if fm.fileExists(atPath: assets.path) {
                try fm.copyItem(at: assets, to: destination.appendingPathComponent("assets"))
            }
        } catch {
            throw InstallError.copyFailed(error.localizedDescription)
        }

        // Re-read from the install location so the returned value points at the copy.
        let installedManifest = try ExtensionManifest.load(directory: destination)
        return InstalledExtension(manifest: installedManifest, directory: destination)
    }

    /// Both paths an extension owns. The scratch directory is the extension's own, so nothing else
    /// will ever collect it — and the uninstall dialog promises it goes.
    static func uninstall(_ installed: InstalledExtension) throws {
        try? FileManager.default.removeItem(at: supportPath(for: installed.manifest.name))
        try FileManager.default.removeItem(at: installed.directory)
    }

    /// Extensions available to import from a locally installed Raycast, newest first. Raycast keys each
    /// install by UUID, so the manifest is the only way to know what a directory holds.
    nonisolated static func importableFromRaycast() -> [InstalledExtension] {
        let fm = FileManager.default
        let entries = raycastExtensionRoots().flatMap { root in
            (try? fm.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        }
        return
            entries
            .compactMap { directory -> InstalledExtension? in
                guard let manifest = try? ExtensionManifest.load(directory: directory),
                    manifest.supportsMacOS,
                    // Skip half-installed or source-only directories.
                    manifest.commands.contains(where: {
                        fm.fileExists(atPath: directory.appendingPathComponent("\($0.name).js").path)
                    })
                else { return nil }
                return InstalledExtension(manifest: manifest, directory: directory)
            }
            // Both channels can hold the same extension; the earlier root wins, so it is offered once.
            .reduce(into: [InstalledExtension]()) { unique, candidate in
                guard !unique.contains(where: { $0.manifest.name == candidate.manifest.name }) else {
                    return
                }
                unique.append(candidate)
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}
