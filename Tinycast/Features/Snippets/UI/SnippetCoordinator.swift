import AppKit

/// Owns the snippet flow: listener, browser, editor handoff, delivery, presence.
@MainActor
final class SnippetCoordinator {
    private let store: SnippetsStore
    private let listener: SnippetKeywordListener
    private let injector: TextInjector
    private let clipboardStore: ClipboardStore
    private let appIndex: AppIndex
    private let settings: AppSettings
    private let windowController: PaletteWindowController
    private let paletteCoordinator: PaletteCoordinator
    private let settingsCoordinator: SettingsCoordinator
    /// Routed out so `MessageHUDController` stays owned by `AppCore`.
    private let showMessage: @MainActor (String) -> Void
    /// The consent dialog and the `pendingSnippetEdit` handoff to the Settings pane.
    private unowned let core: AppCore

    init(
        store: SnippetsStore,
        listener: SnippetKeywordListener,
        injector: TextInjector,
        clipboardStore: ClipboardStore,
        appIndex: AppIndex,
        settings: AppSettings,
        windowController: PaletteWindowController,
        paletteCoordinator: PaletteCoordinator,
        settingsCoordinator: SettingsCoordinator,
        showMessage: @escaping @MainActor (String) -> Void,
        core: AppCore
    ) {
        self.store = store
        self.listener = listener
        self.injector = injector
        self.clipboardStore = clipboardStore
        self.appIndex = appIndex
        self.settings = settings
        self.windowController = windowController
        self.paletteCoordinator = paletteCoordinator
        self.settingsCoordinator = settingsCoordinator
        self.showMessage = showMessage
        self.core = core
    }

    // MARK: - Feature switch

    func revealSnippetsInFinder() {
        NSWorkspace.shared.open(store.snippetsDirectory)
    }

    /// The switch funnels here so enabling, which is also consent, confirms first.
    func setSnippetsEnabled(_ enabled: Bool) {
        guard enabled != settings.snippetsEnabled else { return }
        if !enabled {
            settings.snippetsEnabled = false
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        Task {
            guard
                await core.confirm(
                    title: "Enable snippets?",
                    message:
                        "Keyword expansion requires the Accessibility permission. Keystrokes stay on this Mac.",
                    symbol: "curlybraces", confirmTitle: "Continue", tone: .neutral,
                    confirmRole: .standard)
            else { return }

            settings.snippetsEnabled = true
            // The one prompt for this feature, raised from the gesture that asked for it.
            Permissions.ensureAccessibility()
        }
    }

    // MARK: - Feature presence

    /// Either switch off means the feature reaches the launcher not at all — rows and commands.
    func applySnippetsLauncherPresence() {
        let visible = settings.snippetsEnabled && settings.snippetsShowInLauncher
        appIndex.setCommandsVisible([.searchSnippets, .createSnippet], visible)
        appIndex.updateSnippets(visible ? store.snippets : [])
    }

    /// Reconciles everything the switch owns; off tears down in dependency order.
    func applySnippetsEnabled() {
        if settings.snippetsEnabled {
            Task { await store.start() }
            // An unchanged library publishes no snapshot, so re-project what the store holds.
            applySnippetsLauncherPresence()
            startSnippetKeywordListener()
            return
        }
        listener.stop()
        injector.cancelAutomaticExpansion()
        store.stop()
        applySnippetsLauncherPresence()
    }

    // MARK: - Browsing and editing

    /// The switch gates the browser, the way Search Files re-checks its own before opening.
    func showSnippets() {
        guard settings.snippetsEnabled else { return }
        paletteCoordinator.togglePalette(mode: .snippets)
    }

    /// Opens the Snippets pane with the editor showing `record`; nil is a new snippet.
    func editSnippet(_ record: StoredSnippet?) {
        core.pendingSnippetEdit = SnippetEditRequest(record: record)
        settingsCoordinator.showSettings(tab: .snippets)
    }

    func showSnippetInFinder(_ record: StoredSnippet) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(record.fileURL)
    }

    // MARK: - Expansion

    /// How far back `{clipboard offset=N}` reaches; deeper isn't a snippet idiom.
    private static let clipboardHistoryDepth = 20

    func startSnippetKeywordListener() {
        // `beginAutomaticExpansion` is the gate, so this callback doesn't re-check anything.
        listener.start(
            onUserActivity: { [weak self] in self?.injector.cancelAutomaticExpansion() },
            onMatch: { [weak self] id, keyword, keywordLength, targetApp in
                guard let self,
                    let generation = self.injector.beginAutomaticExpansion(
                        targetApp: targetApp)
                else { return }
                self.expandSnippet(
                    id: id,
                    targetApp: targetApp,
                    expectedKeyword: keyword,
                    keywordLength: keywordLength,
                    automaticGeneration: generation)
            })
    }

    /// Recent copies, newest first; the live pasteboard leads, the poller may lag behind.
    func clipboardHistoryForExpansion() -> [String] {
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

    /// The browser's ↵. The target has to be read before the panel hides, as the launcher's does.
    func expandSnippetFromPalette(id: StoredSnippet.ID) {
        let target = windowController.previousApp
        paletteCoordinator.hidePalette(restoreFocus: false)
        expandSnippet(id: id, targetApp: target)
    }

    func expandSnippet(
        id: StoredSnippet.ID,
        targetApp: NSRunningApplication?,
        expectedKeyword: String? = nil,
        keywordLength: Int = 0,
        automaticGeneration: UInt? = nil
    ) {
        let records = store.snippets
        guard let record = records.first(where: { $0.id == id }) else {
            injector.cancelArgumentPrompt(
                automaticGeneration: automaticGeneration,
                targetApp: targetApp)
            return
        }
        // Only the interactive path needs this: it must fail before the prompt, not after.
        if automaticGeneration == nil {
            guard injector.prepareInteractiveExpansion(targetApp: targetApp) else { return }
        }
        let confirmation = record.snippet.showsConfirmation ? "Inserted \(record.snippet.name)" : nil
        let context = injector.captureExpansionContext(
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
        guard
            let arguments = SnippetArgumentsPrompt.run(
                snippetName: record.snippet.name,
                arguments: missingArgs)
        else {
            injector.cancelArgumentPrompt(
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
        injector.deliver(
            InjectedText(result.text, cursorOffsetFromEnd: result.cursorOffsetFromEnd),
            targetApp: targetApp,
            expectedKeyword: expectedKeyword,
            keywordLength: keywordLength,
            automaticGeneration: automaticGeneration,
            onDelivered: { [weak self] in
                guard let self, let confirmation else { return }
                self.showMessage(confirmation)
            })
    }
}
