import AppKit
import Combine
import SwiftUI

enum PaletteMode: String, CaseIterable, Identifiable {
    case launcher
    case clipboard
    case calculatorHistory
    case emoji

    var id: String { rawValue }
    var title: String {
        switch self {
        case .launcher: return "Apps"
        case .clipboard: return "Clipboard"
        case .calculatorHistory: return "Calculator History"
        case .emoji: return "Emoji & Symbols"
        }
    }
    var systemImage: String {
        switch self {
        case .launcher: return "magnifyingglass"
        case .clipboard: return "doc.on.doc"
        case .calculatorHistory: return "plus.forwardslash.minus"
        case .emoji: return "face.smiling"
        }
    }
    var placeholder: String {
        switch self {
        case .launcher: return "Search for apps and commands…"
        case .clipboard: return "Type to filter entries…"
        case .calculatorHistory: return "Do math, convert units, or search your past calculations…"
        case .emoji: return "Search emoji and symbols…"
        }
    }
}

/// The app a paste will land in, resolved once per palette show so the footer pill and menu rows can name it without re-reading `NSWorkspace` on every render.
struct PasteTarget: Equatable {
    let name: String
    /// Bundle path for `IconCache` — nil for a target with no on-disk bundle.
    let iconPath: String?

    init?(app: NSRunningApplication?) {
        guard let app, let name = app.localizedName else { return nil }
        self.name = name
        iconPath = app.bundleURL?.path
    }

    var pasteTitle: String { "Paste to \(name)" }
}

/// View-model shared between the panel's SwiftUI tree and the coordinator.
@MainActor
final class PaletteViewModel: ObservableObject {
    @Published var mode: PaletteMode = .launcher
    @Published var query: String = ""
    @Published var selection: Int = 0
    /// Changes every time the palette is shown so the search field can re-focus.
    @Published var focusToken = UUID()
    /// Changes only when `prepare` resets the palette, so the lists snap their scroll to the top even when query/mode were already at their defaults (`focusToken` can't serve: it bumps on every reopen, which must preserve a within-timeout scroll).
    @Published var resetToken = UUID()
    /// Changes when an action reorders the list under the selection (pinning a clip lifts it into the Pinned section), so the list scrolls the highlight back into view.
    @Published var followToken = UUID()
    /// Set by the compact bar's "…" overflow to expand into the full launcher without a query; cleared on every `prepare`.
    @Published var forceExpanded = false
    /// The app a paste would land in, mirrored from `PaletteWindowController.previousApp` on every show. Deliberately *not* cleared by `prepare` — pop-to-root resets the screen, not the paste target.
    @Published var pasteTarget: PasteTarget?
    /// Gates the mouse-hover highlight: true only while the pointer is physically moving (armed on `.mouseMoved`, disarmed on any `.keyDown` in `PalettePanel.sendEvent`). Plain, not `@Published` — read at hover time, never drives a re-render.
    var hoverHighlightArmed = false
    /// True while a footer popover menu (⌘K Actions or the app menu) is open, so `PalettePanel.sendEvent` swallows text-editing keystrokes the field editor would otherwise consume — the query must stay frozen while a menu owns the keyboard (matches Raycast). Plain, not `@Published` — read at event time, mirrored from the view's menu state.
    var menuOpen = false { didSet { onMenuOpenChanged?(menuOpen) } }
    /// Fired when `menuOpen` flips so `PalettePanel` can hide/show the search field's caret while it keeps first-responder status (no focus swap, so the placeholder never reflows).
    var onMenuOpenChanged: ((Bool) -> Void)?

    func prepare(mode: PaletteMode) {
        self.mode = mode
        query = ""
        selection = 0
        forceExpanded = false
        hoverHighlightArmed = false
        menuOpen = false
        focusToken = UUID()
        resetToken = UUID()
    }
}

/// Single owner of every long-lived manager. Wired up once from the app delegate.
@MainActor
final class AppCore: ObservableObject {
    static let shared = AppCore()

    let launcherRanking: LauncherRankingStore
    let appIndex: AppIndex
    let customCommands = CustomCommandStore()
    let clipboardStore = ClipboardStore()
    let clipboardManager: ClipboardManager
    let snippetsStore: SnippetsStore
    let snippetListener = SnippetKeywordListener(
        syntheticEventTag: Paster.tinycastEventTag)
    let snippetTextInjector: SnippetTextInjector
    let hotKeys = HotKeyManager()
    let hyperKeyTap = HyperKeyTap()
    let settings: AppSettings
    let favorites = FavoritesStore()
    let visibility = VisibilityStore()
    let calcHistory = CalculatorHistoryStore()
    let currencyRates = CurrencyRateStore()
    let emojiIndex = EmojiIndex()
    let frequentEmoji = FrequentEmojiStore()
    let runningApps = RunningAppsMonitor()
    let palette = PaletteViewModel()

    private lazy var windowController = PaletteWindowController(core: self)
    private lazy var hud = HUDWindowController(settings: settings)
    private let auxWindows = AuxWindowController()
    /// Every confirmation, failure report and value prompt in the app; it also guards against a held hotkey stacking dialogs.
    private let modals = ModalWindowController()
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let launcherRanking = LauncherRankingStore()
        let settings = AppSettings()
        self.launcherRanking = launcherRanking
        self.settings = settings
        appIndex = AppIndex(ranking: launcherRanking)
        let clipboardManager = ClipboardManager(store: clipboardStore, settings: settings)
        self.clipboardManager = clipboardManager
        snippetsStore = SnippetsStore()
        snippetTextInjector = SnippetTextInjector(
            clipboardManager: clipboardManager,
            settings: settings)
    }

    func start() {
        // AppKit's default tooltip delay is ~2–3s; shorten it (in ms) so the compact-bar favorite tooltips appear promptly. Registration domain — never overrides a user default.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 250])
        NSApp.setActivationPolicy(.accessory)
        // Force dark: the Liquid Glass material is tuned for a deep dark surface and renders washed-out in Light mode.
        NSApp.appearance = NSAppearance(named: .darkAqua)

        clipboardStore.maxAge = settings.clipboardRetention.maxAge
        // Defer the initial SQLite read + stale-image prune off the synchronous launch path so the menu bar is interactive immediately; `items` is @Published, so the palette fills in when it lands.
        Task { clipboardStore.load() }
        clipboardManager.start()

        appIndex.start(settings: settings)
        customCommands.onChange = { [weak self] _ in
            self?.applyCustomCommandsPresence()
        }
        applyCustomCommandsPresence()
        Task { await appIndex.refresh() }
        Task { await emojiIndex.load() }
        currencyRates.start()

        hotKeys.onTogglePalette = { [weak self] in self?.togglePalette() }
        hotKeys.onToggleClipboard = { [weak self] in self?.toggleClipboard() }
        hotKeys.onToggleEmoji = { [weak self] in self?.toggleEmoji() }
        hotKeys.onRunCustomCommand = { [weak self] id in self?.runCustomCommand(id: id) }
        hotKeys.start(customCommandIDs: Set(customCommands.commands.map(\.id)))
        // Deliberately keeps running while `hotKeys.recordingAction` pauses Carbon: the recorder relies on the tap's rewritten flags to capture Hyper shortcuts.
        hyperKeyTap.start(settings: settings)

        snippetsStore.onSnapshot = { [weak self] snapshot in
            guard let self else { return }
            self.applySnippetsLauncherPresence()
            self.snippetListener.update(snapshot.records)
        }
        // Off out of the box, so a user who never enables snippets pays for no load, no watcher and no tap.
        if settings.snippetsEnabled {
            Task { await snippetsStore.start() }
            startSnippetKeywordListener()
        }

        // @Published emits synchronously before the property is written (as in `AppIndex.start`), so every re-projection defers to a task that reads the settled value.
        for publisher in [settings.$customCommandsEnabled, settings.$customCommandsShowInLauncher] {
            publisher.dropFirst()
                .sink { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        Task { self.applyCustomCommandsPresence() }
                    }
                }
                .store(in: &cancellables)
        }
        settings.$snippetsEnabled.dropFirst()
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    Task { self.applySnippetsEnabled() }
                }
            }
            .store(in: &cancellables)
        settings.$snippetsShowInLauncher.dropFirst()
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    Task { self.applySnippetsLauncherPresence() }
                }
            }
            .store(in: &cancellables)

        // First launch has no palette hotkey bound and shows nothing but the menu-bar icon; guide the user once. Marker is written at show-time so it stays one-time even if they Cmd-Q mid-flow.
        if !OnboardingState.hasOnboarded {
            OnboardingState.markShown()
            showOnboarding()
        }
    }

    func prepareForTermination() {
        // Caps Lock first: its HID remap is the only teardown that outlives the process, so nothing else may come before it.
        hyperKeyTap.prepareForTermination()
        snippetTextInjector.prepareForTermination()
        snippetListener.stop()
        snippetsStore.stop()
    }

    // MARK: - Feature switches

    private func applyCustomCommandsPresence() {
        let visible = settings.customCommandsEnabled && settings.customCommandsShowInLauncher
        appIndex.setCustomCommands(visible ? customCommands.commands : [])
    }

    private func applySnippetsLauncherPresence() {
        let visible = settings.snippetsEnabled && settings.snippetsShowInLauncher
        appIndex.updateSnippets(visible ? snippetsStore.snippets : [])
    }

    /// Reconciles everything the snippets switch owns. Off tears down in dependency order; hotkey-free, so nothing else needs unwinding.
    private func applySnippetsEnabled() {
        if settings.snippetsEnabled {
            Task { await snippetsStore.start() }
            // A stop/start round-trip over an unchanged library publishes no snapshot, so re-project the records the store already holds.
            applySnippetsLauncherPresence()
            startSnippetKeywordListener()
            return
        }
        snippetListener.stop()
        snippetTextInjector.cancelAutomaticExpansion()
        snippetsStore.stop()
        appIndex.updateSnippets([])
    }

    // MARK: - Palette control

    func togglePalette() {
        if windowController.isVisible, palette.mode == .launcher {
            hidePalette()
        } else {
            showPalette(mode: .launcher, restoreAnyMode: true)
        }
    }

    func toggleClipboard() {
        if windowController.isVisible, palette.mode == .clipboard {
            hidePalette()
        } else {
            showPalette(mode: .clipboard)
        }
    }

    func toggleEmoji() {
        if windowController.isVisible, palette.mode == .emoji {
            hidePalette()
        } else {
            showPalette(mode: .emoji)
        }
    }

    /// Shows the palette, honoring Pop to Root Search: a reopen within the timeout restores the pre-close state — any mode for the generic summon (`restoreAnyMode`), else only when the preserved mode already matches the requested one.
    func showPalette(mode: PaletteMode, restoreAnyMode: Bool = false) {
        let preserved = windowController.consumePreservedState()
        if !(preserved && (restoreAnyMode || palette.mode == mode)) {
            palette.prepare(mode: mode)
        }
        windowController.show()
        // Re-scan on open so an app uninstalled since the last scan drops out of the launcher.
        if palette.mode == .launcher { Task { await appIndex.refresh() } }
    }

    func hidePalette(restoreFocus: Bool = true) {
        windowController.hide(restoreFocus: restoreFocus)
    }

    /// True when the palette should render as the slim compact bar: compact mode on, launcher root, empty query, and not force-expanded via the "…" overflow.
    var paletteIsCollapsed: Bool {
        settings.compactMode
            && !palette.forceExpanded
            && palette.mode == .launcher
            && palette.query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The compact bar's "…" overflow: expand into the full favorites-pinned launcher without typing.
    func expandFromCompact() {
        palette.forceExpanded = true
    }

    /// Resize the panel to match the current collapsed state; called by the view when `paletteIsCollapsed` flips while open.
    func syncPaletteSize() {
        windowController.applyCollapsed(paletteIsCollapsed)
    }

    /// Dock-icon / reopen: focus an open aux window (About/Settings/Onboarding), else summon the launcher. Decoupled from the individual show paths so activation always works.
    func handleReopen() {
        if auxWindows.focusExisting() { return }
        showPalette(mode: .launcher, restoreAnyMode: true)
    }

    /// Settings runs in its own window (the SwiftUI `Settings` scene is unreliable for accessory apps). A fresh window mounts directly on `tab` (no first-frame flicker); an already-open one is switched in place.
    func showSettings(tab: SettingsTab = .general) {
        let isNew = auxWindows.show(
            id: "settings", title: "Settings", size: CGSize(width: 720, height: 550),
            seamlessTitleBar: true
        ) {
            SettingsRootView(initialTab: tab)
                .environmentObject(self)
                .environmentObject(self.appIndex)
                .environmentObject(self.visibility)
                .environmentObject(self.customCommands)
                .environmentObject(self.snippetsStore)
        }
        if !isNew {
            NotificationCenter.default.post(name: .tinycastSelectSettingsTab, object: tab)
        }
    }

    func showBackupSettings() {
        showSettings(tab: .backup)
    }

    func showAbout() {
        showSettings(tab: .about)
    }

    /// The first-run wizard: palette shortcut, Accessibility, Raycast import. Also re-runnable from Settings.
    func showOnboarding() {
        auxWindows.show(
            id: "onboarding", title: "Welcome to Tinycast",
            size: OnboardingView.windowSize, seamlessTitleBar: true
        ) {
            OnboardingView()
        }
    }

    /// Final onboarding step: close the wizard and drop straight into the launcher.
    func finishOnboarding() {
        auxWindows.close(id: "onboarding")
        showPalette(mode: .launcher)
    }

    // MARK: - Actions invoked from the palette UI

    func launch(_ app: AppEntry, searchQuery: String? = nil) {
        if let searchQuery {
            launcherRanking.record(itemKey: app.preferenceKey, query: searchQuery)
        }
        // Commands dispatch before the palette hides: mode-switching commands keep it open.
        if app.kind == .command {
            if let id = CustomCommand.id(fromEntryID: app.id) {
                runCustomCommand(id: id)
            } else {
                runCommand(app)
            }
            return
        }
        if app.kind == .systemCommand {
            runSystemCommand(app)
            return
        }
        let previous = windowController.previousApp
        hidePalette(restoreFocus: false)
        switch app.kind {
        case .application:
            AppLauncher.launch(app.url)
        case .systemSettings:
            guard let bundleID = app.bundleID else { return }
            AppLauncher.openSettingsPane(bundleID: bundleID)
        case .snippet:
            let snippetID = String(app.id.dropFirst("snippet:".count))
            expandSnippet(id: snippetID, targetApp: previous)
        case .command, .systemCommand:
            break  // handled above
        }
    }

    func resetRanking(for app: AppEntry) {
        launcherRanking.reset(itemKey: app.preferenceKey)
    }

    // MARK: - System commands

    private func runSystemCommand(_ entry: AppEntry) {
        guard let command = SystemCommandCatalog.command(forEntryID: entry.id) else { return }
        let previousApp = windowController.previousApp
        if windowController.isVisible { hidePalette(restoreFocus: false) }
        Task { await perform(command, previousApp: previousApp) }
    }

    /// The one place a system command runs, so the confirmation gate can't be bypassed by the palette, a favorite slot, or the compact bar.
    private func perform(_ command: SystemCommand, previousApp: NSRunningApplication?) async {
        if command.confirmation == .required,
            await !modals.confirm(
                title: Self.confirmationTitle(command),
                message: Self.confirmationMessage(command),
                confirmTitle: command.name, destructive: true)
        {
            return
        }
        do {
            let feedback = try await SystemCommandRunner.run(command.id, previousApp: previousApp)
            if Self.showsVolumeFeedback.contains(command.id) {
                let state = try SystemCommandRunner.outputState()
                modals.showVolumeHUD(level: state.level, muted: state.muted)
            } else if let feedback {
                modals.showToast(symbol: feedback.symbol, title: feedback.title)
            }
        } catch let failure as SystemCommandFailure {
            await presentFailure(name: command.name, failure: failure)
        } catch {
            await presentFailure(
                name: command.name, failure: SystemCommandFailure(error.localizedDescription))
        }
    }

    /// Commands that change the output level or mute state; macOS only draws its own HUD for real media keys, so these get Tinycast's.
    private static let showsVolumeFeedback: Set<SystemCommand.ID> = [
        .toggleMute,
    ]

    private static func confirmationTitle(_ command: SystemCommand) -> String {
        switch command.id {
        case .restart: return "Restart your Mac?"
        case .shutDown: return "Shut down your Mac?"
        case .logOut: return "Log out now?"
        default: return "Run \(command.name)?"
        }
    }

    private static func confirmationMessage(_ command: SystemCommand) -> String {
        switch command.id {
        case .restart, .shutDown, .logOut:
            return "Applications with unsaved changes may ask you to save."
        default: return "This system action may interrupt your work."
        }
    }

    // MARK: - Dialogs
    //
    // Routed through `AppCore` so `modals` stays the single owner; flows outside the palette (the backup
    // actions) reach the same dialogs instead of falling back to an `NSAlert`.

    func showNotice(title: String, message: String, symbol: String = "info.circle") async {
        await modals.notice(title: title, message: message, symbol: symbol)
    }

    func askConfirmation(
        title: String, message: String, confirmTitle: String, destructive: Bool = true
    ) async -> Bool {
        await modals.confirm(
            title: title, message: message, confirmTitle: confirmTitle, destructive: destructive)
    }

    /// Sync entry point for the runner's own async completion handlers, which can't await.
    func presentSystemCommandFailure(name: String, failure: SystemCommandFailure) {
        Task { await presentFailure(name: name, failure: failure) }
    }

    private func presentFailure(name: String, failure: SystemCommandFailure) async {
        let settingsTitle = failure.settings == nil ? nil : "Open System Settings…"
        guard
            await modals.report(
                title: "“\(name)” Failed", message: failure.message,
                settingsTitle: settingsTitle),
            let settings = failure.settings
        else { return }
        let pane: String
        switch settings {
        case .accessibility: pane = "Privacy_Accessibility"
        case .automation: pane = "Privacy_Automation"
        case .bluetooth: pane = "Privacy_Bluetooth"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Custom commands

    @discardableResult
    func addCustomCommand(_ draft: CustomCommand) throws -> CustomCommand {
        try customCommands.add(draft)
    }

    func updateCustomCommand(_ draft: CustomCommand) throws {
        try customCommands.update(draft)
    }

    func deleteCustomCommand(id: UUID) {
        guard let command = customCommands.command(id: id) else { return }
        removeCustomCommandReferences(ids: [id], entryIDs: [command.entryID])
        customCommands.remove(id: id)
    }

    @discardableResult
    func replaceCustomCommands(_ commands: [CustomCommand]) -> Int {
        let previous = Dictionary(uniqueKeysWithValues: customCommands.commands.map { ($0.id, $0) })
        let count = customCommands.replace(with: commands)
        let liveIDs = Set(customCommands.commands.map(\.id))
        let removed = Set(previous.keys).subtracting(liveIDs)
        let removedEntryIDs = Set(removed.compactMap { previous[$0]?.entryID })
        removeCustomCommandReferences(ids: removed, entryIDs: removedEntryIDs)
        return count
    }

    /// The one funnel for both palette activation and the command's global hotkey, so the confirmation gate can't be bypassed by either.
    func runCustomCommand(id: UUID) {
        // Also the feature switch: with custom commands off a still-registered global hotkey must not run anything.
        guard settings.customCommandsEnabled else { return }
        guard let command = customCommands.command(id: id) else { return }
        if windowController.isVisible { hidePalette(restoreFocus: false) }
        Task {
            if command.requiresConfirmation {
                guard
                    await modals.confirm(
                        title: command.name,
                        message: "Are you sure you want to run this command?\n\n\(command.command)",
                        confirmTitle: "Run", destructive: true)
                else { return }
            }
            let outcome = await ShellCommandRunner.run(
                command.command, loadingShellEnvironment: command.loadsShellEnvironment)
            guard outcome != .success else {
                // Fires when the command finishes, not when it starts, so a slow one confirms late rather than lying early.
                if command.showsConfirmation { self.hud.show(message: "Ran \(command.name)") }
                return
            }
            await presentCustomCommandFailure(command: command, outcome: outcome)
        }
    }

    private func removeCustomCommandReferences(ids: Set<UUID>, entryIDs: Set<String>) {
        for id in ids {
            let action = HotKeyAction.customCommand(id: id)
            if hotKeys.recordingAction == action { hotKeys.recordingAction = nil }
            hotKeys.setShortcut(nil, for: action)
        }
        favorites.remove(keys: entryIDs)
        visibility.removeItemKeys(entryIDs)
        for entryID in entryIDs {
            launcherRanking.reset(itemKey: entryID)
        }
    }

    private func presentCustomCommandFailure(
        command: CustomCommand, outcome: ShellCommandOutcome
    ) async {
        let message: String
        // `127` is the shell's "command not found", so an alias or function that only exists in the user's config lands here.
        var suggestsShellEnvironment = false
        switch outcome {
        case .success:
            return
        case .launchFailure(let detail):
            message = "The shell could not be started.\n\n\(detail)"
        case .nonZeroExit(let status, let stderr):
            suggestsShellEnvironment = status == 127 && !command.loadsShellEnvironment
            message =
                "The command exited with status \(status)."
                + (stderr.map { "\n\n" + $0 } ?? "")
                + (suggestsShellEnvironment
                    ? "\n\nIf this is a shell alias or function, turn on Load Shell Environment for "
                        + "this command." : "")
        }
        guard
            await modals.report(
                title: "“\(command.name)” Failed", message: message,
                settingsTitle: suggestsShellEnvironment ? "Open Settings…" : nil)
        else { return }
        showSettings(tab: .customCommands)
    }

    /// Quits the app behind an entry; a no-op (palette stays put) when it isn't running.
    func quit(_ app: AppEntry) {
        guard app.kind == .application, let bundleID = app.bundleID else { return }
        // Unlike `launch`, nothing here takes focus on its own — hand it back to where the user was, unless that's the app now on its way out.
        let quittingPreviousApp = windowController.previousApp?.bundleIdentifier == bundleID
        guard AppLauncher.quit(bundleID: bundleID) else { return }
        hidePalette(restoreFocus: !quittingPreviousApp)
    }

    /// Quit All: the one action whose blast radius reaches outside Tinycast, so it confirms first. The target list is resolved once and both counted and terminated, so the set the user approves is the set that quits.
    private func quitAllApps() async {
        let targets = AppLauncher.quitAllTargets()
        guard !targets.isEmpty,
            await modals.confirm(
                title: targets.count == 1
                    ? "Quit 1 application?" : "Quit \(targets.count) applications?",
                message: "Applications with unsaved changes will ask you to save.",
                confirmTitle: "Quit All", destructive: true)
        else { return }
        for app in targets { app.terminate() }
    }

    private func runCommand(_ entry: AppEntry) {
        switch CommandRegistry.command(for: entry) {
        case .calculatorHistory:
            showPalette(mode: .calculatorHistory)
        case .clipboardHistory:
            showPalette(mode: .clipboard)
        case .searchEmoji:
            showPalette(mode: .emoji)
        case .exportSettings:
            hidePalette(restoreFocus: false)
            Task { await BackupActions.exportSettings() }
        case .importSettings:
            hidePalette(restoreFocus: false)
            Task { await BackupActions.importSettings() }
        case .importFromRaycast:
            hidePalette(restoreFocus: false)
            showBackupSettings()
        case .settings:
            hidePalette(restoreFocus: false)
            showSettings()
        case .about:
            hidePalette(restoreFocus: false)
            showAbout()
        case .quitAllApps:
            // Hide before confirming: the palette is a floating panel and would sit above the dialog.
            hidePalette(restoreFocus: false)
            Task { await quitAllApps() }
        case .quit:
            NSApp.terminate(nil)
        case nil:
            break
        }
    }

    /// Enter on the inline calculator card: copy the answer, remember the calculation, dismiss.
    func copyCalculatorResult(_ result: CalcResult) {
        guard case .value(let display, let copyText) = result.payload else { return }
        calcHistory.record(expression: result.expression, result: display)
        hidePalette(restoreFocus: false)
        Paster.copyPlainText(copyText)
    }

    /// Enter on a Calculator History row: re-copy the stored answer (no re-record).
    func copyHistoryEntry(_ entry: CalcHistoryEntry) {
        hidePalette(restoreFocus: false)
        Paster.copyPlainText(entry.result.replacingOccurrences(of: ",", with: ""))
    }

    func copyHistoryExpression(_ entry: CalcHistoryEntry) {
        hidePalette(restoreFocus: false)
        Paster.copyPlainText(entry.expression)
    }

    func showInFinder(_ app: AppEntry) {
        hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(app.url)
    }

    func paste(_ item: ClipboardItem) {
        let previous = windowController.previousApp
        hidePalette(restoreFocus: false)
        // A successful write promotes the item to the head of its section; follow it so any preserved (pop-to-root) or open clipboard state highlights the row that moved.
        if Paster.paste(item, store: clipboardStore, previousApp: previous) {
            selectClip(item)
        }
    }

    func pasteKeepingWindowOpen(_ item: ClipboardItem) {
        if windowController.pasteKeepingWindowOpen(item, store: clipboardStore) {
            selectClip(item)
        }
    }

    func copyToClipboard(_ item: ClipboardItem) {
        hidePalette(restoreFocus: false)
        if Paster.copy(item, store: clipboardStore) {
            selectClip(item)
        }
    }

    func revealClipboardImage(_ item: ClipboardItem) {
        guard let url = clipboardStore.imageURL(for: item) else { return }
        hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(url)
    }

    /// Pin or unpin a clipboard entry: the row jumps into (or out of) the Pinned section at the top, so the selection and the scroll follow it.
    func togglePinnedClip(_ item: ClipboardItem) {
        clipboardStore.togglePinned(item)
        selectClip(item)
        palette.followToken = UUID()
    }

    /// Put the selection on `item`'s row in the list as currently filtered — pinned rows hold the top, so a row that moved isn't always index 0.
    private func selectClip(_ item: ClipboardItem) {
        palette.selection = clipboardStore.rowIndex(of: item, in: palette.query) ?? 0
    }

    // MARK: - Emoji actions (frequency is tallied on the base glyph; the configured tone is applied at copy time)

    func pasteEmoji(_ entry: EmojiEntry) {
        frequentEmoji.record(entry.glyph)
        let previous = windowController.previousApp
        hidePalette(restoreFocus: false)
        Paster.pasteString(entry.display(tone: settings.emojiSkinTone), previousApp: previous)
    }

    func copyEmoji(_ entry: EmojiEntry) {
        frequentEmoji.record(entry.glyph)
        hidePalette(restoreFocus: false)
        Paster.copyString(entry.display(tone: settings.emojiSkinTone))
    }

    func pasteEmojiKeepingWindowOpen(_ entry: EmojiEntry) {
        frequentEmoji.record(entry.glyph)
        windowController.pasteStringKeepingWindowOpen(entry.display(tone: settings.emojiSkinTone))
    }

    // MARK: - Snippets

    /// How far back `{clipboard offset=N}` can reach; deeper offsets aren't a snippet idiom and this keeps the per-expansion sort trivial.
    private static let clipboardHistoryDepth = 20

    func revealSnippetsInFinder() {
        NSWorkspace.shared.open(snippetsStore.snippetsDirectory)
    }

    /// The pane's switch funnels through here so enabling — which is also keyword-expansion consent — confirms first. The settings sink then reconciles the store, listener and launcher presence.
    func setSnippetsEnabled(_ enabled: Bool) {
        guard enabled != settings.snippetsEnabled else { return }
        if !enabled {
            settings.snippetsEnabled = false
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Enable snippets?"
        alert.informativeText =
            "Keyword expansion requires the Accessibility permission. Keystrokes stay on this Mac."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        settings.snippetsEnabled = true
        // The one prompt for this feature, raised from the gesture that asked for it.
        Permissions.ensureAccessibility()
    }

    private func startSnippetKeywordListener() {
        // `beginAutomaticExpansion` is the gate: it re-checks consent, permission, Secure Event Input and the target on the injector side, so this callback doesn't duplicate it.
        snippetListener.start { [weak self] id, keyword, keywordLength, targetApp in
            guard let self,
                let generation = self.snippetTextInjector.beginAutomaticExpansion(
                    targetApp: targetApp)
            else { return }
            self.expandSnippet(
                id: id,
                targetApp: targetApp,
                expectedKeyword: keyword,
                keywordLength: keywordLength,
                automaticGeneration: generation)
        }
    }

    /// Recent text copies, newest first, for `{clipboard offset=N}`. The live pasteboard leads because the poller may not have recorded the newest copy yet.
    private func clipboardHistoryForExpansion() -> [String] {
        var history = clipboardStore.items
            .filter { $0.kind == .text }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(Self.clipboardHistoryDepth)
            .compactMap(\.text)
        if let current = NSPasteboard.general.string(forType: .string), current != history.first {
            history.insert(current, at: 0)
        }
        return history
    }

    private func expandSnippet(
        id: StoredSnippet.ID,
        targetApp: NSRunningApplication?,
        expectedKeyword: String? = nil,
        keywordLength: Int = 0,
        automaticGeneration: UInt? = nil
    ) {
        let records = snippetsStore.snippets
        guard let record = records.first(where: { $0.id == id }) else {
            snippetTextInjector.cancelArgumentPrompt(
                automaticGeneration: automaticGeneration,
                targetApp: targetApp)
            return
        }
        // The automatic path was gated by `beginAutomaticExpansion` in the same turn, and `deliver` gates both again. Only the interactive path needs a check here: it must fail before the argument prompt, not after it.
        if automaticGeneration == nil {
            guard snippetTextInjector.prepareInteractiveExpansion(targetApp: targetApp) else { return }
        }
        let confirmation = record.snippet.showsConfirmation ? "Inserted \(record.snippet.name)" : nil
        let context = snippetTextInjector.captureExpansionContext(
            targetApp: targetApp,
            clipboardHistory: clipboardHistoryForExpansion())
        let result = SnippetTemplateEngine.expand(
            record,
            snippets: records,
            context: context)
        if !result.missingArguments.isEmpty {
            promptSnippetArguments(
                record: record,
                records: records,
                context: context,
                missingArgs: result.missingArguments,
                targetApp: targetApp,
                expectedKeyword: expectedKeyword,
                keywordLength: keywordLength,
                automaticGeneration: automaticGeneration,
                confirmation: confirmation)
            return
        }
        completeSnippetExpansion(
            result,
            targetApp: targetApp,
            expectedKeyword: expectedKeyword,
            keywordLength: keywordLength,
            automaticGeneration: automaticGeneration,
            confirmation: confirmation)
    }

    private func promptSnippetArguments(
        record: StoredSnippet,
        records: [StoredSnippet],
        context: SnippetTemplateEngine.ExpansionContext,
        missingArgs: [SnippetTemplateEngine.MissingArgument],
        targetApp: NSRunningApplication?,
        expectedKeyword: String?,
        keywordLength: Int,
        automaticGeneration: UInt?,
        confirmation: String?
    ) {
        guard let arguments = SnippetArgumentsPrompt.run(
            snippetName: record.snippet.name,
            arguments: missingArgs)
        else {
            snippetTextInjector.cancelArgumentPrompt(
                automaticGeneration: automaticGeneration,
                targetApp: targetApp)
            return
        }

        let result = SnippetTemplateEngine.expand(
            record,
            snippets: records,
            context: context,
            userArguments: arguments)
        completeSnippetExpansion(
            result,
            targetApp: targetApp,
            expectedKeyword: expectedKeyword,
            keywordLength: keywordLength,
            automaticGeneration: automaticGeneration,
            confirmation: confirmation)
    }

    private func completeSnippetExpansion(
        _ result: SnippetTemplateEngine.ExpansionResult,
        targetApp: NSRunningApplication?,
        expectedKeyword: String?,
        keywordLength: Int,
        automaticGeneration: UInt?,
        confirmation: String?
    ) {
        snippetTextInjector.deliver(
            result,
            targetApp: targetApp,
            expectedKeyword: expectedKeyword,
            keywordLength: keywordLength,
            automaticGeneration: automaticGeneration,
            onDelivered: { [weak self] in
                guard let self, let confirmation else { return }
                self.hud.show(message: confirmation)
            })
    }
}
