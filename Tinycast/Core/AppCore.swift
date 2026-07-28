import AppKit
import SwiftUI
import Carbon.HIToolbox

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
    let snippetsStore = SnippetsStore()
    private(set) var snippetListener: SnippetKeywordListener?
    let hotKeys = HotKeyManager()
    let hyperKeyTap = HyperKeyTap()
    let settings = AppSettings()
    let favorites = FavoritesStore()
    let visibility = VisibilityStore()
    let calcHistory = CalculatorHistoryStore()
    let currencyRates = CurrencyRateStore()
    let emojiIndex = EmojiIndex()
    let frequentEmoji = FrequentEmojiStore()
    let runningApps = RunningAppsMonitor()
    let palette = PaletteViewModel()

    private lazy var windowController = PaletteWindowController(core: self)
    private let auxWindows = AuxWindowController()
    /// Guards only the confirmation modal, not execution — two deliberate runs of an unguarded command still run twice.
    private var isConfirmingCommand = false

    private init() {
        let launcherRanking = LauncherRankingStore()
        self.launcherRanking = launcherRanking
        appIndex = AppIndex(ranking: launcherRanking)
        clipboardManager = ClipboardManager(store: clipboardStore, settings: settings)
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
        customCommands.onChange = { [weak self] commands in
            self?.appIndex.setCustomCommands(commands)
        }
        appIndex.setCustomCommands(customCommands.commands)
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

        snippetListener = SnippetKeywordListener(store: snippetsStore)
        snippetListener?.start { [weak self] snippet, missingArgs in
            self?.promptSnippetArguments(snippet: snippet, missingArgs: missingArgs)
        }

        // First launch has no palette hotkey bound and shows nothing but the menu-bar icon; guide the user once. Marker is written at show-time so it stays one-time even if they Cmd-Q mid-flow.
        if !OnboardingState.hasOnboarded {
            OnboardingState.markShown()
            showOnboarding()
        }
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
                .environmentObject(self.appIndex)
                .environmentObject(self.visibility)
                .environmentObject(self.customCommands)
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
        let previous = windowController.previousApp
        hidePalette(restoreFocus: false)
        switch app.kind {
        case .application:
            AppLauncher.launch(app.url)
        case .systemSettings:
            guard let bundleID = app.bundleID else { return }
            AppLauncher.openSettingsPane(bundleID: bundleID)
        case .snippet:
            let snippetIDString = app.id.replacingOccurrences(of: "snippet:", with: "")
            guard let snippet = snippetsStore.snippets.first(where: { $0.id.uuidString == snippetIDString || $0.name == app.name }) else { return }

            let result = SnippetTemplateEngine.expand(snippet, snippets: snippetsStore.snippets)
            if !result.missingArguments.isEmpty {
                promptSnippetArguments(snippet: snippet, missingArgs: result.missingArguments)
            } else {
                Paster.injectString(result.text, previousApp: previous)
                if let offset = result.cursorOffsetFromEnd, offset > 0 {
                    let source = CGEventSource(stateID: .combinedSessionState)
                    for i in 0..<offset {
                        DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.008 + 0.1) {
                            guard let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_LeftArrow), keyDown: true),
                                  let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_LeftArrow), keyDown: false) else { return }
                            down.setIntegerValueField(.eventSourceUserData, value: Paster.tinycastEventTag)
                            up.setIntegerValueField(.eventSourceUserData, value: Paster.tinycastEventTag)
                            if let pid = previous?.processIdentifier {
                                down.postToPid(pid)
                                up.postToPid(pid)
                            } else {
                                down.post(tap: .cgAnnotatedSessionEventTap)
                                up.post(tap: .cgAnnotatedSessionEventTap)
                            }
                        }
                    }
                }
            }
        case .command:
            break  // handled above
        }
    }

    func resetRanking(for app: AppEntry) {
        launcherRanking.reset(itemKey: app.preferenceKey)
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
        guard let command = customCommands.command(id: id) else { return }
        // Hide before confirming: the palette is a floating panel and would sit above the alert.
        if windowController.isVisible { hidePalette(restoreFocus: false) }
        if command.requiresConfirmation {
            // Carbon hotkeys keep firing during a modal session; without this a held shortcut stacks alerts.
            guard !isConfirmingCommand else { return }
            isConfirmingCommand = true
            defer { isConfirmingCommand = false }
            guard Self.confirmRun(command) else { return }
        }
        Task {
            let outcome = await ShellCommandRunner.run(
                command.command, loadingShellEnvironment: command.loadsShellEnvironment)
            guard outcome != .success else { return }
            self.presentCustomCommandFailure(command: command, outcome: outcome)
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

    private static func confirmRun(_ command: CustomCommand) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = command.name
        alert.informativeText = "Are you sure you want to run this command?"
        alert.alertStyle = .warning
        let runButton = alert.addButton(withTitle: "Run")
        // ↵ goes to Cancel, as in `confirmQuitAll`: this command is one ↵ away in the palette.
        runButton.keyEquivalent = ""
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\r"
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func presentCustomCommandFailure(
        command: CustomCommand, outcome: ShellCommandOutcome
    ) {
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
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "“\(command.name)” Failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        if suggestsShellEnvironment { alert.addButton(withTitle: "Open Settings…") }
        guard alert.runModal() == .alertSecondButtonReturn else { return }
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
    private func quitAllApps() {
        let targets = AppLauncher.quitAllTargets()
        guard !targets.isEmpty, Self.confirmQuitAll(count: targets.count) else { return }
        for app in targets { app.terminate() }
    }

    private static func confirmQuitAll(count: Int) -> Bool {
        // An accessory app's alert opens behind the frontmost app unless it activates first (same as `BackupActions`).
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = count == 1 ? "Quit 1 application?" : "Quit \(count) applications?"
        alert.informativeText = "Applications with unsaved changes will ask you to save."
        alert.alertStyle = .warning
        let quitButton = alert.addButton(withTitle: "Quit All")
        quitButton.hasDestructiveAction = true
        // `hasDestructiveAction` only tints the button — it stays the ↵ default. Hand ↵ to Cancel instead: this command is one ↵ away in the palette, and a second reflexive ↵ must not quit the desktop.
        quitButton.keyEquivalent = ""
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\r"
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func runCommand(_ entry: AppEntry) {
        switch CommandRegistry.command(for: entry) {
        case .calculatorHistory:
            showPalette(mode: .calculatorHistory)
        case .clipboardHistory:
            showPalette(mode: .clipboard)
        case .searchEmoji:
            showPalette(mode: .emoji)
        case .searchSnippets:
            hidePalette(restoreFocus: false)
            showSettings(tab: .snippets)
        case .exportSettings:
            hidePalette(restoreFocus: false)
            BackupActions.exportSettings()
        case .importSettings:
            hidePalette(restoreFocus: false)
            BackupActions.importSettings()
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
            // Hide before confirming: the palette is a floating panel and would sit above the alert.
            hidePalette(restoreFocus: false)
            quitAllApps()
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

    // MARK: - Snippet Argument Prompt

    func promptSnippetArguments(snippet: Snippet, missingArgs: [String]) {
        let frontApp = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Snippet: \(snippet.name)"
        alert.informativeText = "Fill in the required template fields:"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Expand")
        alert.addButton(withTitle: "Cancel")

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 8
        stackView.frame = NSRect(x: 0, y: 0, width: 320, height: CGFloat(missingArgs.count * 52))

        var fields: [String: NSTextField] = [:]

        for arg in missingArgs {
            let label = NSTextField(labelWithString: "\(arg):")
            label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            let field = NSTextField(string: "")
            field.placeholderString = arg
            fields[arg] = field

            stackView.addArrangedSubview(label)
            stackView.addArrangedSubview(field)
            field.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
        }

        alert.accessoryView = stackView

        if alert.runModal() == .alertFirstButtonReturn {
            var userArgs: [String: String] = [:]
            for (arg, field) in fields {
                userArgs[arg] = field.stringValue
            }
            let result = SnippetTemplateEngine.expand(snippet, snippets: snippetsStore.snippets, userArguments: userArgs)
            Paster.injectString(result.text, previousApp: frontApp)

            if let offset = result.cursorOffsetFromEnd, offset > 0 {
                let source = CGEventSource(stateID: .combinedSessionState)
                for i in 0..<offset {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.008 + 0.1) {
                        guard let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_LeftArrow), keyDown: true),
                              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_LeftArrow), keyDown: false) else { return }
                        down.setIntegerValueField(.eventSourceUserData, value: Paster.tinycastEventTag)
                        up.setIntegerValueField(.eventSourceUserData, value: Paster.tinycastEventTag)
                        if let pid = frontApp?.processIdentifier {
                            down.postToPid(pid)
                            up.postToPid(pid)
                        } else {
                            down.post(tap: .cgAnnotatedSessionEventTap)
                            up.post(tap: .cgAnnotatedSessionEventTap)
                        }
                    }
                }
            }
        }
    }
}
