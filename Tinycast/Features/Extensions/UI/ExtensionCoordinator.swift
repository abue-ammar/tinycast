import AppKit

/// Owns how a Raycast extension command meets the palette: launching one, leaving it, and the host
/// callbacks (`closeMainWindow`, `popToRoot`, `showHUD`…) the running command can make.
///
/// `ExtensionManager` owns the runtime and the installed set; everything that shows, hides or
/// re-points a surface goes through here, so no other type reaches into the palette on its behalf.
@MainActor
final class ExtensionCoordinator {
    private let extensions: ExtensionManager
    private let palette: PaletteState
    private let paletteCoordinator: PaletteCoordinator
    private let settingsCoordinator: SettingsCoordinator
    private let settings: AppSettings
    /// Message-HUD presentation only — never for state this type owns.
    private unowned let core: AppCore

    init(
        extensions: ExtensionManager,
        palette: PaletteState,
        paletteCoordinator: PaletteCoordinator,
        settingsCoordinator: SettingsCoordinator,
        settings: AppSettings,
        core: AppCore
    ) {
        self.extensions = extensions
        self.palette = palette
        self.paletteCoordinator = paletteCoordinator
        self.settingsCoordinator = settingsCoordinator
        self.settings = settings
        self.core = core
    }

    /// A view command takes over the palette; a no-view command closes it and runs headless.
    func runExtensionCommand(_ app: AppEntry, arguments: [String: String] = [:]) {
        guard let (owner, command) = extensions.resolve(app) else { return }
        switch command.mode {
        case .view:
            // Switch the palette over first, so the launching state is what the user sees.
            palette.prepare(mode: .extensionCommand)
            Task { await extensions.run(owner, command: command, arguments: arguments) }
        case .noView, .menuBar:
            // A no-view command's own `showHUD` / `showToast` is the feedback; the palette gets out of
            // the way exactly as Raycast does. An unsupported mode surfaces its reason as a HUD.
            paletteCoordinator.hidePalette(restoreFocus: false)
            Task { await extensions.run(owner, command: command, arguments: arguments) }
        }
    }

    /// The arguments a selected launcher row declares, or nil when it isn't an extension command with
    /// any — what the header uses to decide whether to show the inline argument fields.
    func commandArguments(for entry: AppEntry?) -> [ExtensionCommandArgument]? {
        guard let entry, entry.kind == .extensionCommand,
            let (_, command) = extensions.resolve(entry), !command.arguments.isEmpty
        else { return nil }
        return command.arguments
    }

    /// Escape in an extension screen: pop the extension's own stack first, then leave the command.
    func exitExtensionScreen() {
        Task {
            if await extensions.popNavigation() { return }
            await extensions.stop()
            palette.prepare(mode: .launcher)
        }
    }

    /// `popToRoot()` from an extension — back to a fresh root search, command torn down.
    func popExtensionToRoot() {
        Task {
            await extensions.stop()
            palette.prepare(mode: .launcher)
        }
    }

    func showExtensionSettings(for owner: InstalledExtension) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        settingsCoordinator.showSettings(tab: .extensions)
        NotificationCenter.default.post(
            name: .tinycastSelectExtension, object: owner.manifest.name)
    }

    // MARK: - Host callbacks, routed here so the manager never touches a window itself

    /// The app a paste from an extension should land in — the same recorded target the clipboard and
    /// emoji paste paths use.
    var pasteTarget: NSRunningApplication? { paletteCoordinator.targetApp }

    /// `getApplications()` reports what the launcher itself indexes, so the two never disagree.
    var applicationURLs: [URL] { SearchScopes.appBundles(in: settings.searchScopes) }

    /// True while the palette is on screen — a toast has somewhere to render only then.
    var isPaletteVisible: Bool { paletteCoordinator.isVisible }

    func closeMainWindow() {
        paletteCoordinator.hidePalette(restoreFocus: false)
    }

    func reopenPalette(hasRunningCommand: Bool) {
        paletteCoordinator.showPalette(
            mode: hasRunningCommand ? .extensionCommand : .launcher, restoreAnyMode: true)
    }

    func clearSearchBar() {
        palette.query = ""
    }

    /// `showHUD` from an extension. Its own window, because a no-view command closes the palette
    /// before it finishes — the pill has to outlive it.
    func showHUD(_ message: String) {
        core.showMessage(message)
    }
}

extension Notification.Name {
    /// Carries an extension's name so the Settings pane can select it once shown.
    static let tinycastSelectExtension = Notification.Name("tinycastSelectExtension")
}
