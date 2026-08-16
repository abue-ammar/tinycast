import AppKit

/// How a command meets the palette: launching, leaving, and the host callbacks it can make.
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

    // MARK: - Feature presence

    /// Applies both switches as they stand — on launch, and after a backup import moves them.
    func applyEnabled() {
        extensions.setShowsInLauncher(settings.extensionsShowInLauncher)
        Task { await extensions.setEnabled(settings.extensionsEnabled) }
    }

    /// Also consent to run third-party JavaScript, so it asks before it starts.
    func setExtensionsEnabled(_ enabled: Bool) {
        guard enabled != settings.extensionsEnabled else { return }
        guard enabled else {
            settings.extensionsEnabled = false
            Task { await extensions.setEnabled(false) }
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        Task {
            guard
                await core.confirm(
                    title: "Enable extensions?",
                    message:
                        "Extensions are third-party JavaScript, run on this Mac. A running command "
                        + "holds a JavaScript engine in memory until you leave it — expect Tinycast "
                        + "to use noticeably more RAM while one is open.",
                    symbol: "puzzlepiece.extension", confirmTitle: "Enable", tone: .neutral,
                    confirmRole: .standard)
            else { return }

            settings.extensionsEnabled = true
            await extensions.setEnabled(true)
        }
    }

    func applyExtensionsLauncherPresence() {
        extensions.setShowsInLauncher(settings.extensionsShowInLauncher)
    }

    /// Resolved from the installed set: the launcher may never have been opened.
    func runExtensionCommand(entryID: String) {
        guard settings.extensionsEnabled,
            let entry = extensions.launcherEntry(forEntryID: entryID)
        else { return }
        runExtensionCommand(entry)
    }

    // MARK: - Managing one extension from the launcher

    /// Opens Settings on the extension a launcher row belongs to.
    func showExtensionSettings(for app: AppEntry) {
        guard let (owner, _) = extensions.resolve(app) else { return }
        showExtensionSettings(for: owner)
    }

    /// The palette hides before the dialog: it floats, and a sheet behind it is unreachable.
    func confirmUninstall(_ app: AppEntry) {
        guard let (owner, _) = extensions.resolve(app) else { return }
        confirmUninstall(owner)
    }

    func confirmUninstall(_ owner: InstalledExtension) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        NSApp.activate(ignoringOtherApps: true)
        Task {
            guard
                await core.confirm(
                    title: "Uninstall \(owner.title)?",
                    message:
                        "Removes the extension and everything it stored — its preferences, its cache "
                        + "and its own files. Its commands leave the launcher.",
                    symbol: "trash", confirmTitle: "Uninstall")
            else { return }
            await extensions.uninstall(owner)
        }
    }

    /// Destructive: an orphaned support directory is an extension's own files, so it asks first.
    func confirmCleanup(_ report: ExtensionCleanup.Report) async {
        guard !report.isEmpty else { return }
        let size = ExtensionCleanup.formatted(bytes: report.bytes)
        guard
            await core.confirm(
                title: "Clean up \(size)?",
                message:
                    "Removes build files left by an interrupted install, and the storage of "
                    + "extensions that are no longer installed. Installed extensions are untouched.",
                symbol: "trash", confirmTitle: "Clean Up")
        else { return }

        let installed = Set(extensions.installed.map(\.manifest.name))
        let roots = ExtensionCleanup.defaultRoots()
        let freed = await Task.detached(priority: .userInitiated) {
            ExtensionCleanup.clean(installed: installed, in: roots)
        }.value
        core.showMessage(
            freed.isEmpty
                ? "Nothing to clean up" : "Reclaimed \(ExtensionCleanup.formatted(bytes: freed.bytes))")
    }

    /// What no index prunes: left behind, these key a shortcut or a rank to a vanished command.
    func removeExtensionReferences(entryIDs: [String]) {
        for entryID in entryIDs {
            let action = HotKeyAction.extensionCommand(entryID: entryID)
            if core.hotKeys.recordingAction == action { core.hotKeys.recordingAction = nil }
            core.hotKeys.setBinding(nil, for: action)
            core.launcherRanking.reset(itemKey: entryID)
        }
        core.favorites.remove(keys: Set(entryIDs))
        core.visibility.removeItemKeys(Set(entryIDs))
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
            // A no-view command's own HUD is the feedback, so the palette gets out of the way.
            paletteCoordinator.hidePalette(restoreFocus: false)
            Task { await extensions.run(owner, command: command, arguments: arguments) }
        }
    }

    /// The arguments a row declares, or nil — what decides whether the header shows inline fields.
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

    /// `confirmAlert` from an extension. The dialog outranks the palette's level, so a view command
    /// keeps its screen behind the question.
    func confirmExtensionAlert(_ alert: ExtensionAlert) async -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        return await core.confirm(
            title: alert.title, message: alert.message,
            symbol: alert.isDestructive ? "exclamationmark.triangle" : "questionmark.circle",
            confirmTitle: alert.primaryTitle,
            tone: alert.isDestructive ? .danger : .neutral,
            confirmRole: alert.isDestructive ? .destructive : .standard,
            dismissTitle: alert.dismissTitle)
    }
}

extension Notification.Name {
    /// Carries an extension's name so the Settings pane can select it once shown.
    static let tinycastSelectExtension = Notification.Name("tinycastSelectExtension")
}
