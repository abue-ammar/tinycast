import AppKit

/// Single owner of every long-lived manager. Wired up once from the app delegate.
@MainActor
@Observable
final class AppCore {
    static let shared = AppCore()

    let launcherRanking: LauncherRankingStore
    let appIndex: AppIndex
    let customCommands = CustomCommandStore()
    let quicklinks = QuicklinkStore()
    let clipboardStore = ClipboardStore()
    let clipboardManager: ClipboardManager
    let snippetsStore: SnippetsStore
    let snippetListener = SnippetKeywordListener(
        syntheticEventTag: Paster.tinycastEventTag)
    let snippetTextInjector: SnippetTextInjector
    let hotKeys = HotKeyManager()
    let hyperKeyTap = HyperKeyTap()
    let windowMover = WindowMover()
    let settings: AppSettings
    let favorites = FavoritesStore()
    let visibility = VisibilityStore()
    let calcHistory = CalculatorHistoryStore()
    let currencyRates = CurrencyRateStore()
    let emojiIndex = EmojiIndex()
    let frequentEmoji = FrequentEmojiStore()
    let runningApps = RunningAppsMonitor()
    let palette = PaletteState()
    let fileSearch = FileSearchSession()
    let activationPolicy = ActivationPolicy()
    let uninstall = UninstallSession()
    let quicklinkArguments = QuicklinkArgumentSession()
    let extensions: ExtensionManager

    /// Set when a quicklink editor should open with Settings; the pane consumes it.
    var pendingQuicklinkEdit: QuicklinkEditRequest?

    @ObservationIgnored private(set) lazy var snippetExpansion = SnippetExpansionCoordinator(
        store: snippetsStore, listener: snippetListener, injector: snippetTextInjector,
        clipboardStore: clipboardStore, appIndex: appIndex, settings: settings,
        showMessage: { [unowned self] in self.showMessage($0) }, core: self)
    @ObservationIgnored private(set) lazy var quicklinkCoordinator = QuicklinkCoordinator(
        store: quicklinks, argumentSession: quicklinkArguments, settings: settings,
        appIndex: appIndex, injector: snippetTextInjector, hotKeys: hotKeys, favorites: favorites,
        visibility: visibility, ranking: launcherRanking, windowController: windowController,
        paletteCoordinator: paletteCoordinator, settingsCoordinator: settingsCoordinator,
        clipboardHistory: { [unowned self] in self.snippetExpansion.clipboardHistoryForExpansion() },
        core: self)

    @ObservationIgnored private(set) lazy var paletteCoordinator = PaletteCoordinator(
        palette: palette, settings: settings, appIndex: appIndex,
        fileSearch: fileSearch,
        windowController: windowController)
    /// Its own window and lifecycle: neither coordinator shows or closes the other's surface.
    @ObservationIgnored private(set) lazy var settingsCoordinator = SettingsCoordinator(core: self)
    @ObservationIgnored private(set) lazy var onboardingCoordinator = OnboardingCoordinator(
        core: self)
    @ObservationIgnored private(set) lazy var systemActionCoordinator = SystemActionCoordinator(
        paletteCoordinator: paletteCoordinator, core: self)
    @ObservationIgnored private(set) lazy var uninstallCoordinator = UninstallCoordinator(
        session: uninstall, palette: palette, paletteCoordinator: paletteCoordinator,
        appIndex: appIndex, runningApps: runningApps, hotKeys: hotKeys, favorites: favorites,
        visibility: visibility, ranking: launcherRanking, core: self)
    @ObservationIgnored private(set) lazy var extensionCoordinator = ExtensionCoordinator(
        extensions: extensions, palette: palette, paletteCoordinator: paletteCoordinator,
        settingsCoordinator: settingsCoordinator, settings: settings, core: self)
    @ObservationIgnored private(set) lazy var windowCommandCoordinator = WindowCommandCoordinator(
        settings: settings, paletteCoordinator: paletteCoordinator, windowMover: windowMover)
    @ObservationIgnored private(set) lazy var customCommandCoordinator = CustomCommandCoordinator(
        store: customCommands, settings: settings, appIndex: appIndex,
        paletteCoordinator: paletteCoordinator, settingsCoordinator: settingsCoordinator,
        hotKeys: hotKeys, favorites: favorites, visibility: visibility,
        ranking: launcherRanking, core: self)

    @ObservationIgnored private(set) lazy var launcherCoordinator = LauncherCoordinator(
        ranking: launcherRanking, windowController: windowController,
        paletteCoordinator: paletteCoordinator,
        settingsCoordinator: settingsCoordinator,
        customCommandCoordinator: customCommandCoordinator,
        systemActionCoordinator: systemActionCoordinator,
        quicklinkCoordinator: quicklinkCoordinator,
        windowCommandCoordinator: windowCommandCoordinator,
        snippetExpansion: snippetExpansion, fileSearchCoordinator: fileSearchCoordinator,
        extensionCoordinator: extensionCoordinator, core: self)
    @ObservationIgnored private(set) lazy var clipboardCoordinator = ClipboardCoordinator(
        clipboardStore: clipboardStore, palette: palette, windowController: windowController,
        paletteCoordinator: paletteCoordinator, core: self)
    @ObservationIgnored private(set) lazy var emojiCoordinator = EmojiCoordinator(
        frequentEmoji: frequentEmoji, settings: settings, windowController: windowController,
        paletteCoordinator: paletteCoordinator)
    @ObservationIgnored private(set) lazy var calculatorCoordinator = CalculatorCoordinator(
        calcHistory: calcHistory, paletteCoordinator: paletteCoordinator, core: self)
    @ObservationIgnored private(set) lazy var fileSearchCoordinator = FileSearchCoordinator(
        settings: settings, appIndex: appIndex, session: fileSearch, palette: palette,
        paletteCoordinator: paletteCoordinator, core: self)

    @ObservationIgnored private lazy var windowController = PaletteWindowController(core: self)
    @ObservationIgnored private lazy var messageHUD = MessageHUDController(settings: settings)
    /// Every confirmation, report and prompt; it also stops a held hotkey stacking them.
    private let dialogs = DialogController()
    private let healthTicker = HealthTicker()

    private init() {
        let launcherRanking = LauncherRankingStore()
        let settings = AppSettings()
        self.launcherRanking = launcherRanking
        self.settings = settings
        appIndex = AppIndex(ranking: launcherRanking)
        let clipboardManager = ClipboardManager(store: clipboardStore, settings: settings)
        self.clipboardManager = clipboardManager
        extensions = ExtensionManager(clipboardStore: clipboardStore)
        snippetsStore = SnippetsStore()
        snippetTextInjector = SnippetTextInjector(
            clipboardManager: clipboardManager,
            settings: settings)
    }

    func start() {
        Signposts.interval("AppCore.start") {
            // Shorten AppKit's ~2–3s tooltip delay; registration domain, so a user default wins.
            UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 250])
            NSApp.setActivationPolicy(.accessory)
            // Force dark: the Liquid Glass material is tuned for a deep dark surface.
            NSApp.appearance = NSAppearance(named: .darkAqua)

            clipboardStore.maxAge = settings.clipboardRetention.maxAge
            // Defer the SQLite read + prune off the launch path; the palette fills in later.
            Task { clipboardStore.load() }
            clipboardManager.start()

            appIndex.start(settings: settings)
            extensions.start(appIndex: appIndex, coordinator: extensionCoordinator)
            extensionCoordinator.applyEnabled()
            fileSearchCoordinator.applyEnabled()
            fileSearchCoordinator.applyPolicy()
            customCommands.onChange = { [weak self] _ in
                self?.customCommandCoordinator.applyCustomCommandsPresence()
            }
            customCommandCoordinator.applyCustomCommandsPresence()
            applyWindowCommandsPresence()
            quicklinks.onChange = { [weak self] _ in
                self?.quicklinkCoordinator.applyQuicklinksPresence()
            }
            // Before `hotKeys.start` even when off: the prune reads it. docs/features/quicklinks.md
            quicklinks.load()
            quicklinkCoordinator.applyQuicklinksPresence()
            Task { await appIndex.refresh() }
            Task { await emojiIndex.load() }
            currencyRates.start()

            hyperKeyTap.healthTicker = healthTicker
            hotKeys.doubleTapMonitor.healthTicker = healthTicker
            snippetListener.healthTicker = healthTicker

            hotKeys.onTogglePalette = { [weak self] in self?.paletteCoordinator.togglePalette() }
            hotKeys.onToggleClipboard = { [weak self] in self?.paletteCoordinator.toggleClipboard() }
            hotKeys.onToggleEmoji = { [weak self] in self?.paletteCoordinator.toggleEmoji() }
            hotKeys.onSearchFiles = { [weak self] in self?.fileSearchCoordinator.show() }
            hotKeys.onRunCustomCommand = { [weak self] id in
                self?.customCommandCoordinator.runCustomCommand(id: id)
            }
            hotKeys.onRunSystemAction = { [weak self] id in
                self?.systemActionCoordinator.runSystemAction(id: id)
            }
            hotKeys.onRunWindowCommand = { [weak self] id in
                self?.windowCommandCoordinator.runWindowCommand(id: id)
            }
            hotKeys.onOpenQuicklink = { [weak self] id in
                self?.quicklinkCoordinator.openQuicklink(id: id)
            }
            hotKeys.onRunExtensionCommand = { [weak self] entryID in
                self?.extensionCoordinator.runExtensionCommand(entryID: entryID)
            }
            extensions.onDidUninstall = { [weak self] entryIDs in
                self?.extensionCoordinator.removeExtensionReferences(entryIDs: entryIDs)
            }
            hotKeys.displayName = { [weak self] action in self?.hotKeyDisplayName(for: action) }
            KeyShortcut.displayedHyperChord = { [settings] in
                guard settings.hyperKey != .none else { return nil }
                return KeyShortcut.hyperChord(includesShift: settings.hyperKeyIncludesShift)
            }
            SystemActionRunner.onAsyncFailure = { [weak self] id, failure in
                self?.systemActionCoordinator.presentSystemActionFailure(id: id, failure: failure)
            }
            hotKeys.start(
                customCommandIDs: Set(customCommands.commands.map(\.id)),
                quicklinkIDs: Set(quicklinks.quicklinks.map(\.id)))
            // Keeps running while Carbon pauses: the recorder needs its rewritten flags.
            hyperKeyTap.start(settings: settings)

            snippetsStore.onSnapshot = { [weak self] snapshot in
                guard let self else { return }
                self.snippetExpansion.applySnippetsLauncherPresence()
                self.snippetListener.update(snapshot.records)
            }
            // Off out of the box, so an unused feature costs no load, watcher or tap.
            if settings.snippetsEnabled {
                Task { await snippetsStore.start() }
                snippetExpansion.startSnippetKeywordListener()
            }

            observeFeatureSwitches()

            // First launch binds no hotkey, so guide once; the marker is written at show-time.
            if !OnboardingState.hasOnboarded {
                OnboardingState.markShown()
                onboardingCoordinator.showOnboarding()
            }
        }
    }

    /// Clicking the Dock icon: raise whichever window is already open, else summon the launcher.
    func handleReopen() {
        if settingsCoordinator.focusExisting() { return }
        if onboardingCoordinator.focusExisting() { return }
        paletteCoordinator.showPalette(mode: .launcher, restoreAnyMode: true)
    }

    /// The store-backed half of the conflict message; `HotKeyManager` names the catalogs itself.
    private func hotKeyDisplayName(for action: HotKeyAction) -> String? {
        switch action {
        case .app(let bundleID):
            return appIndex.apps.first { $0.kind == .application && $0.bundleID == bundleID }?.name
        case .settingsPane(let bundleID):
            return appIndex.apps.first { $0.kind == .systemSettings && $0.bundleID == bundleID }?
                .name
        case .customCommand(let id):
            return customCommands.command(id: id)?.name
        case .quicklink(let id):
            return quicklinks.quicklink(id: id)?.name
        case .extensionCommand(let entryID):
            return appIndex.apps.first { $0.kind == .extensionCommand && $0.id == entryID }?.name
        case .togglePalette, .toggleClipboard, .toggleEmoji, .searchFiles, .systemAction,
            .windowCommand:
            return nil
        }
    }

    func prepareForTermination() {
        // Caps Lock first: its remap is the one teardown that outlives the process.
        hyperKeyTap.prepareForTermination()
        snippetTextInjector.prepareForTermination()
        snippetListener.stop()
        snippetsStore.stop()
    }

    // MARK: - Feature switches

    private func observeFeatureSwitches() {
        track(
            {
                _ = $0.windowManagementEnabled
                _ = $0.windowManagementShowInLauncher
            }, reproject: { $0.applyWindowCommandsPresence() })
        track(
            {
                _ = $0.customCommandsEnabled
                _ = $0.customCommandsShowInLauncher
            }, reproject: { $0.customCommandCoordinator.applyCustomCommandsPresence() })
        track(
            {
                _ = $0.quicklinksEnabled
                _ = $0.quicklinksShowInLauncher
            }, reproject: { $0.quicklinkCoordinator.applyQuicklinksPresence() })
        track({ _ = $0.fileSearchEnabled }, reproject: { $0.fileSearchCoordinator.applyEnabled() })
        track(
            {
                _ = $0.fileSearchScopes
                _ = $0.fileSearchIgnorePatterns
            }, reproject: { $0.fileSearchCoordinator.applyPolicy() })
        track({ _ = $0.snippetsEnabled }, reproject: { $0.snippetExpansion.applySnippetsEnabled() })
        // Not a feature switch, but the same re-projection: a combo has the chord's ⇧ bit baked in.
        track({ _ = $0.hyperKeyIncludesShift }, reproject: { $0.applyHyperChord() })
        track(
            { _ = $0.snippetsShowInLauncher },
            reproject: { $0.snippetExpansion.applySnippetsLauncherPresence() })
    }

    /// Fires synchronously on main before the write lands, so the task re-arms and re-reads.
    private func track(
        _ reads: @escaping @Sendable @MainActor (AppSettings) -> Void,
        reproject: @escaping @Sendable @MainActor (AppCore) -> Void
    ) {
        withObservationTracking {
            reads(settings)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.track(reads, reproject: reproject)
                reproject(self)
            }
        }
    }

    /// Without a Hyper key the chord means nothing, so a literal ⌃⌥⌘ combo is left as recorded.
    private func applyHyperChord() {
        guard settings.hyperKey != .none else { return }
        hotKeys.retargetHyperBindings(includesShift: settings.hyperKeyIncludesShift)
    }

    private func applyWindowCommandsPresence() {
        let visible = settings.windowManagementEnabled && settings.windowManagementShowInLauncher
        appIndex.setWindowCommandsVisible(visible)
    }

    // MARK: - Dialogs, routed here so `dialogs` stays the single owner

    func showNotice(title: String, message: String, symbol: String, tone: DialogTone) async {
        await dialogs.notice(title: title, message: message, symbol: symbol, tone: tone)
    }

    /// `tone` styles the glyph, `confirmRole` the button; separate on purpose.
    func confirm(
        title: String, message: String?, symbol: String, confirmTitle: String,
        tone: DialogTone = .danger, confirmRole: DialogAction.Role = .destructive,
        dismissTitle: String = "Cancel"
    ) async -> Bool {
        await dialogs.confirm(
            title: title, message: message, symbol: symbol, tone: tone, confirmTitle: confirmTitle,
            confirmRole: confirmRole, dismissTitle: dismissTitle)
    }

    /// A failure with one usable second option; `true` when the user takes it.
    func reportFailure(
        title: String, message: String, symbol: String, recovery: String?
    ) async
        -> Bool
    {
        await dialogs.reportFailure(
            title: title, message: message, symbol: symbol, recovery: recovery)
    }

    /// The transient success/info pill, so `messageHUD` stays single-owned alongside `dialogs`.
    func showMessage(_ message: String, tone: DialogTone = .success) {
        messageHUD.show(message: message, tone: tone)
    }

    /// The volume slider, so `dialogs` stays the single owner of every prompt in the app.
    func pickVolume(current: Float32) async -> Float32? {
        await dialogs.pickVolume(current: current)
    }
}
