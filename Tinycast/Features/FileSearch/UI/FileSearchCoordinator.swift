import AppKit

@MainActor
final class FileSearchCoordinator {
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let session: FileSearchSession
    private let palette: PaletteState
    private let paletteCoordinator: PaletteCoordinator
    private unowned let core: AppCore

    init(
        settings: AppSettings, appIndex: AppIndex, session: FileSearchSession,
        palette: PaletteState, paletteCoordinator: PaletteCoordinator, core: AppCore
    ) {
        self.settings = settings
        self.appIndex = appIndex
        self.session = session
        self.palette = palette
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    func applyEnabled() {
        appIndex.setCommandsVisible([.searchFiles], settings.fileSearchEnabled)
        guard !settings.fileSearchEnabled else { return }
        session.cancel()
        if palette.mode == .fileSearch { palette.prepare(mode: .launcher) }
    }

    func applyPolicy() {
        session.apply(
            scopes: settings.fileSearchScopes, ignorePatterns: settings.fileSearchIgnorePatterns)
    }

    /// `query` is the fallback row's: the screen opens already narrowed to what was typed.
    func show(query: String = "") {
        guard settings.fileSearchEnabled else { return }
        let seedQuery: String?
        if !query.isEmpty {
            seedQuery = query
        } else if let lastActive = session.lastActiveAt,
            Date().timeIntervalSince(lastActive) < settings.fileSearchResetTimeout.interval,
            !session.lastQuery.isEmpty
        {
            seedQuery = session.lastQuery
        } else {
            seedQuery = nil
        }
        paletteCoordinator.togglePalette(mode: .fileSearch, seeding: seedQuery)
    }

    func toggleInfoPanel() {
        session.toggleInfoPanel()
    }

    func open(_ result: FileSearchResult) {
        closeQuickLook()
        paletteCoordinator.hidePalette(restoreFocus: false)
        Task {
            do {
                _ = try await NSWorkspace.shared.open(
                    result.url, configuration: NSWorkspace.OpenConfiguration())
            } catch {
                await core.showNotice(
                    title: "Couldn’t Open \(result.name)",
                    message: error.localizedDescription,
                    symbol: result.isDirectory ? "folder" : "doc", tone: .danger)
            }
        }
    }

    func showInFinder(_ result: FileSearchResult) {
        closeQuickLook()
        paletteCoordinator.hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(result.url)
    }

    func quickLook(_ result: FileSearchResult) {
        FileQuickLookController.shared.toggle(url: result.url)
    }

    func updateQuickLookIfVisible(_ result: FileSearchResult?) {
        guard let result else { return }
        FileQuickLookController.shared.updateIfVisible(url: result.url)
    }

    func closeQuickLook() {
        FileQuickLookController.shared.close()
    }

    func showInfoInFinder(_ result: FileSearchResult) {
        let path = result.url.path.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"Finder\" to open information window of (POSIX file \"\(path)\" as alias)"
        Task.detached {
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
        }
    }

    func copyFile(_ result: FileSearchResult) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([result.url as NSURL])
        core.showMessage("Copied file")
    }

    func copyName(_ result: FileSearchResult) {
        Paster.copyPlainText(result.name)
        core.showMessage("Copied name")
    }

    func copyPath(_ result: FileSearchResult) {
        Paster.copyPlainText(result.id)
        core.showMessage("Copied path")
    }

    func saveAsQuicklink(_ result: FileSearchResult) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        core.quicklinkCoordinator.editQuicklink(
            Quicklink(name: result.name, link: result.url.absoluteString))
    }
}
