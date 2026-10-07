import AppKit

@MainActor
final class ExtensionStoreCoordinator {
    let session: ExtensionStoreSession
    private let extensions: ExtensionManager
    private let palette: PaletteState
    private let paletteCoordinator: PaletteCoordinator
    private unowned let core: AppCore
    private var installed: [InstalledExtension] = []
    private var scanTask: Task<Void, Never>?
    private var installs: [String: Task<Void, Never>] = [:]

    init(
        session: ExtensionStoreSession, extensions: ExtensionManager, palette: PaletteState,
        paletteCoordinator: PaletteCoordinator, core: AppCore
    ) {
        self.session = session
        self.extensions = extensions
        self.palette = palette
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    func show() {
        paletteCoordinator.showPalette(mode: .extensionStore)
    }

    func opening() {
        if palette.mode == .extensionStore { search(palette.query) }
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            let installed = await Task.detached(priority: .userInitiated) { ExtensionCatalog.scan() }.value
            guard !Task.isCancelled, let self else { return }
            self.installed = installed
            self.session.setInstalledNames(Set(installed.map(\.manifest.name)))
            if self.session.installedOnly { self.search(self.palette.query) }
        }
    }

    var metrics: InterfaceMetrics { core.settings.interfaceSize.metrics }

    func search(_ query: String) {
        guard session.installedOnly else { session.search(query); return }
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = installed.filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
                || $0.manifest.commands.contains { $0.title.localizedCaseInsensitiveContains(query) }
        }
        session.showInstalled(matching.map(Self.listing))
    }

    func retry() {
        session.search(palette.query, force: true)
    }

    private static func listing(_ installed: InstalledExtension) -> ExtensionListing {
        let manifest = installed.manifest
        let icon = installed.iconPath.map { URL(filePath: $0) }
        return ExtensionListing(
            id: manifest.name, name: manifest.name, title: manifest.title,
            summary: manifest.description, author: manifest.author,
            lightIconURL: icon, darkIconURL: icon, commandCount: manifest.commands.count,
            downloadCount: nil, downloadURL: installed.directory, commitSHA: nil,
            authorHandle: manifest.author, ownerHandle: manifest.storeHandle,
            commands: manifest.commands.map {
                ExtensionListing.Command(name: $0.name, title: $0.title, summary: $0.description, mode: $0.mode.rawValue)
            }, categories: manifest.categories)
    }

    func selectCategory(_ category: String?) {
        session.installedOnly = category == "Installed"
        session.category = session.installedOnly ? nil : category
        palette.selection = 0
        if session.installedOnly { search(palette.query) } else { session.search(palette.query, force: true) }
    }

    func details(_ listing: ExtensionListing) {
        session.showDetails(listing)
        paletteCoordinator.navigate(to: .extensionStoreDetails)
    }

    func isInstalled(_ listing: ExtensionListing) -> Bool {
        extensions.installed.contains { $0.manifest.name == listing.name }
            || session.installedNames.contains(listing.name)
    }

    func primaryTitle(for listing: ExtensionListing) -> String {
        if let progress = session.progress[listing.name] { return progress }
        return isInstalled(listing) ? "Open Extension" : "Install Extension"
    }

    func canActivate(_ listing: ExtensionListing) -> Bool {
        guard session.progress[listing.name] == nil else { return false }
        if isInstalled(listing) { return true }
        guard !listing.downloadURL.isFileURL else { return false }
        return palette.mode != .extensionStoreDetails || (!session.detailLoading && session.detailFailure == nil)
    }

    func activate(_ listing: ExtensionListing) {
        guard canActivate(listing) else { return }
        if let installed = (extensions.installed + installed).first(where: { $0.manifest.name == listing.name }) {
            core.extensionCoordinator.showExtensionSettings(for: installed)
            return
        }
        install(listing)
    }

    func install(_ listing: ExtensionListing) {
        guard installs[listing.name] == nil else { return }
        session.installFailures[listing.name] = nil
        session.progress[listing.name] = ExtensionInstaller.Progress.downloading.message
        installs[listing.name] = Task { [weak self] in
            guard let self else { return }
            defer {
                self.session.progress[listing.name] = nil
                self.installs[listing.name] = nil
            }
            guard await self.core.extensionCoordinator.enableExtensions() else { return }
            do {
                try await self.extensions.install(listing) { [weak self] progress in
                    Task { @MainActor in
                        guard let self, self.installs[listing.name] != nil else { return }
                        self.session.progress[listing.name] = progress.message
                    }
                }
                self.scanTask?.cancel()
                self.installed = self.extensions.installed
                self.session.setInstalledNames(Set(self.installed.map(\.manifest.name)))
                self.core.showMessage("\(listing.title) installed", tone: .success)
            } catch {
                self.session.installFailures[listing.name] = error.localizedDescription
                self.core.showMessage("Couldn't install \(listing.title)", tone: .danger)
            }
        }
    }

    func uninstall(_ listing: ExtensionListing) {
        guard let installed = (extensions.installed + installed).first(where: { $0.manifest.name == listing.name }) else {
            return
        }
        core.extensionCoordinator.confirmUninstall(installed)
    }

    func open(_ url: URL) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        AppLauncher.open(url)
    }

    func restoreSelection() {
        guard let detail = session.detail, let index = session.listings.firstIndex(where: { $0.name == detail.name }) else {
            return
        }
        palette.selection = index
    }

    func suspend() { session.suspend() }
    func close() {
        scanTask?.cancel()
        session.close()
    }

    isolated deinit {
        scanTask?.cancel()
        for task in installs.values { task.cancel() }
    }
}
