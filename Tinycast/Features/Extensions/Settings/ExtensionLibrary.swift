import Foundation

/// An extension change Settings awaits: the main app makes every one, since it runs them.
enum ExtensionCall: Codable, Sendable {
    case refresh
    case checkForUpdates
    case installFolder(URL)
    case importFromRaycast([URL])
    case update([String])
    case installListing(ExtensionListing)
    case installGitHub(ExtensionGitHubSource)
    case uninstall(String)
}

enum ExtensionCallEvent: Codable, Sendable {
    case installing(ExtensionInstaller.Progress)
    case imported(Int)
}

struct ExtensionCallResult: Codable, Sendable {
    /// Titles a batch could not import or update.
    var failures: [String] = []
    /// A single install's failure, as its pane words it.
    var error: String?
    var installedTitle: String?
}

struct ExtensionCallError: LocalizedError {
    let errorDescription: String?
}

/// Settings' extensions: the catalog from disk, the main app's state, and every change asked of it.
@MainActor
@Observable
final class ExtensionLibrary {
    private(set) var installed: [InstalledExtension] = []
    /// Set in this window; the main app stores them, since this process never writes storage.
    private var editedPreferences: [String: ExtensionPreferenceValue?] = [:]

    @ObservationIgnored private let mainApp: MainAppLink
    @ObservationIgnored private let storage = ExtensionStorage(directory: ExtensionCatalog.storageDirectory())

    init(mainApp: MainAppLink) {
        self.mainApp = mainApp
    }

    private var mirrored: MainAppStatus.Extensions { mainApp.status.extensions }
    var updates: [String: String] { mirrored.updates }
    var updating: Set<String> { mirrored.updating }
    var catalogRevision: Int { mirrored.catalogRevision }

    func rescan() async {
        installed = await Task.detached(priority: .utility) { ExtensionCatalog.scan() }.value
    }

    func refresh() async {
        _ = await mainApp.call(.refresh)
        await rescan()
    }

    func checkForUpdates() async {
        _ = await mainApp.call(.checkForUpdates)
    }

    func install(from source: URL) async throws {
        try await changeCatalog(.installFolder(source))
    }

    func install(
        _ listing: ExtensionListing, onProgress: @escaping (ExtensionInstaller.Progress) -> Void
    ) async throws {
        try await changeCatalog(.installListing(listing), onProgress: onProgress)
    }

    /// Returns the installed title, for the panel to announce.
    func install(
        _ source: ExtensionGitHubSource, onProgress: @escaping (ExtensionInstaller.Progress) -> Void
    ) async throws -> String {
        try await changeCatalog(.installGitHub(source), onProgress: onProgress).installedTitle ?? ""
    }

    func importAllFromRaycast(
        _ candidates: [InstalledExtension], onProgress: @escaping (Int) -> Void
    ) async -> [String] {
        let result = await mainApp.call(.importFromRaycast(candidates.map(\.directory))) { event in
            if case .imported(let done) = event { onProgress(done) }
        }
        await rescan()
        return result.failures
    }

    func update(_ names: [String]) async -> [String] {
        let result = await mainApp.call(.update(names))
        await rescan()
        return result.failures
    }

    func uninstall(_ owner: InstalledExtension) async {
        _ = await mainApp.call(.uninstall(owner.manifest.name))
        await rescan()
    }

    /// Scanned off-main: it reads a manifest per directory, and a full Raycast install is dozens.
    func raycastImportCandidates() async -> [RaycastImportCandidate] {
        let candidates = await Task.detached(priority: .userInitiated) {
            ExtensionCatalog.importableFromRaycast()
        }.value
        let have = Set(installed.map(\.manifest.name))
        return candidates.map {
            RaycastImportCandidate(installed: $0, isInstalled: have.contains($0.manifest.name))
        }
    }

    /// Leftovers are files only, so this process clears them against the disk's own catalog.
    func cleanUp() async -> ExtensionCleanup.Report {
        let installed = Set(installed.map(\.manifest.name))
        let roots = ExtensionCleanup.defaultRoots()
        return await Task.detached(priority: .userInitiated) {
            ExtensionCleanup.clean(installed: installed, in: roots)
        }.value
    }

    func appearance(for name: String) -> ExtensionAppearance? {
        mirrored.appearances[name]
    }

    func setAppearance(_ appearance: ExtensionAppearance?, for name: String) {
        mainApp.send(.setExtensionAppearance(name, appearance))
    }

    func backgroundInfo(extension name: String, command: String) -> ExtensionCommandMetadata {
        mirrored.commands[ExtensionCommandRef(extensionName: name, commandName: command).entryID]
            ?? ExtensionCommandMetadata()
    }

    func setBackgroundEnabled(_ enabled: Bool, extension name: String, command: String) {
        mainApp.send(
            .setExtensionBackground(ExtensionCommandRef(extensionName: name, commandName: command), enabled))
    }

    func menuBarIsEnabled(_ reference: ExtensionCommandRef) -> Bool {
        mirrored.commands[reference.entryID]?.menuBarEnabled ?? false
    }

    func setMenuBarEnabled(_ enabled: Bool, reference: ExtensionCommandRef) {
        mainApp.send(.setExtensionMenuBar(reference, enabled))
    }

    func preference(extension name: String, key: String) -> ExtensionPreferenceValue? {
        if let edited = editedPreferences[name + "/" + key] { return edited }
        return storage.preference(extension: name, key: key)
    }

    func setPreference(extension name: String, key: String, value: ExtensionPreferenceValue?) {
        editedPreferences[name + "/" + key] = .some(value)
        mainApp.send(.setExtensionPreference(name, key: key, value))
    }

    @discardableResult
    private func changeCatalog(
        _ call: ExtensionCall, onProgress: @escaping (ExtensionInstaller.Progress) -> Void = { _ in }
    ) async throws -> ExtensionCallResult {
        let result = await mainApp.call(call) { event in
            if case .installing(let progress) = event { onProgress(progress) }
        }
        await rescan()
        if let error = result.error { throw ExtensionCallError(errorDescription: error) }
        return result
    }
}
