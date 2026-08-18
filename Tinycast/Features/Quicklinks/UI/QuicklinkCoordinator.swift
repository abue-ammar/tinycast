import AppKit

/// Owns the quicklink flow: the open funnel, the argument prompt, the library and import/export.
@MainActor
final class QuicklinkCoordinator {
    private let store: QuicklinkStore
    private let argumentSession: QuicklinkArgumentSession
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let injector: SnippetTextInjector
    private let hotKeys: HotKeyManager
    private let favorites: FavoritesStore
    private let visibility: VisibilityStore
    private let ranking: LauncherRankingStore
    private let aliases: AliasStore
    private let windowController: PaletteWindowController
    private let paletteCoordinator: PaletteCoordinator
    private let settingsCoordinator: SettingsCoordinator
    /// `{clipboard offset=N}` reads the history a snippet expansion does; one owner, one depth.
    private let clipboardHistory: @MainActor () -> [String]
    /// Dialogs, the HUD, and the `pendingQuicklinkEdit` handoff to the Settings pane.
    private unowned let core: AppCore

    /// Carries the menu's default-app override across the quicklink argument prompt.
    private var pendingQuicklinkForcesDefaultApp = false

    init(
        store: QuicklinkStore,
        argumentSession: QuicklinkArgumentSession,
        settings: AppSettings,
        appIndex: AppIndex,
        injector: SnippetTextInjector,
        hotKeys: HotKeyManager,
        favorites: FavoritesStore,
        visibility: VisibilityStore,
        ranking: LauncherRankingStore,
        aliases: AliasStore,
        windowController: PaletteWindowController,
        paletteCoordinator: PaletteCoordinator,
        settingsCoordinator: SettingsCoordinator,
        clipboardHistory: @escaping @MainActor () -> [String],
        core: AppCore
    ) {
        self.store = store
        self.argumentSession = argumentSession
        self.settings = settings
        self.appIndex = appIndex
        self.injector = injector
        self.hotKeys = hotKeys
        self.favorites = favorites
        self.visibility = visibility
        self.ranking = ranking
        self.aliases = aliases
        self.windowController = windowController
        self.paletteCoordinator = paletteCoordinator
        self.settingsCoordinator = settingsCoordinator
        self.clipboardHistory = clipboardHistory
        self.core = core
    }

    // MARK: - Feature presence

    /// The switch moves section and commands together; "show in launcher" hides only the section.
    func applyQuicklinksPresence() {
        let enabled = settings.quicklinksEnabled
        appIndex.setQuicklinks(
            enabled && settings.quicklinksShowInLauncher ? store.quicklinks : [])
        appIndex.setCommandsVisible(
            [.createQuicklink, .searchQuicklinks, .importQuicklinks, .exportQuicklinks],
            enabled)
    }

    // MARK: - Opening

    /// The one funnel for every open, so neither the switch nor the prompt can be bypassed.
    func openQuicklink(id: UUID, forcingDefaultApp: Bool = false) {
        guard settings.quicklinksEnabled, let quicklink = store.quicklink(id: id) else {
            return
        }
        // With the palette closed a shortcut still reads the selection from the frontmost app.
        let target =
            windowController.isVisible
            ? windowController.previousApp : NSWorkspace.shared.frontmostApplication
        let encoding: SnippetTemplateEngine.ValueEncoding =
            QuicklinkDestination.usesURLEncoding(quicklink.link) ? .percentEncoding : .none
        var context = injector.captureExpansionContext(
            targetApp: target, clipboardHistory: clipboardHistory())
        var arguments: [SnippetTemplateEngine.MissingArgument] = []

        // An unreadable selection is missing, not empty: substitute the clipboard, or prompt.
        if context.selection.isEmpty, SnippetTemplateEngine.usesSelection(quicklink.link) {
            switch settings.quicklinkSelectionFallback {
            case .clipboard:
                context = context.replacingSelection(with: context.clipboard)
            case .ask:
                arguments.append(Self.selectionArgument)
            }
        }

        let expansion = SnippetTemplateEngine.expand(
            text: quicklink.link, context: context, encoding: encoding)
        arguments += expansion.missingArguments
        guard arguments.isEmpty else {
            argumentSession.begin(
                quicklink: quicklink, context: context, encoding: encoding, arguments: arguments)
            pendingQuicklinkForcesDefaultApp = forcingDefaultApp
            // Never `restoreAnyMode`: this screen is always a fresh prompt, never a restored one.
            paletteCoordinator.showPalette(mode: .quicklinkArguments)
            return
        }
        performQuicklinkOpen(
            quicklink, link: expansion.text, forcingDefaultApp: forcingDefaultApp)
    }

    /// `{selection}` promoted to an argument when unreadable and the setting says ask.
    private static let selectionArgument = SnippetTemplateEngine.MissingArgument(
        name: "Selected Text", options: [])

    /// ↵ in the argument form. Returns false while more arguments remain.
    @discardableResult
    func submitQuicklinkArgument(_ value: String) -> Bool {
        guard let request = argumentSession.request else { return false }
        guard let values = argumentSession.submit(value) else { return false }

        var context = request.context
        if let selection = values[Self.selectionArgument.name] {
            context = context.replacingSelection(with: selection)
        }
        let expansion = SnippetTemplateEngine.expand(
            text: request.quicklink.link, context: context, userArguments: values,
            encoding: request.encoding)
        let forcesDefault = pendingQuicklinkForcesDefaultApp
        cancelQuicklinkArguments()
        performQuicklinkOpen(
            request.quicklink, link: expansion.text, forcingDefaultApp: forcesDefault)
        return true
    }

    func cancelQuicklinkArguments() {
        argumentSession.cancel()
        pendingQuicklinkForcesDefaultApp = false
    }

    private func performQuicklinkOpen(
        _ quicklink: Quicklink, link: String, forcingDefaultApp: Bool
    ) {
        if windowController.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
        let openWith = forcingDefaultApp ? nil : quicklink.openWithBundleID
        Task {
            do throws(QuicklinkLauncher.Failure) {
                try await QuicklinkLauncher.open(
                    link, openWithBundleID: openWith,
                    inNewWindow: settings.quicklinkOpensNewWindow)
            } catch {
                await presentQuicklinkFailure(quicklink, link: link, failure: error)
            }
        }
    }

    private func presentQuicklinkFailure(
        _ quicklink: Quicklink, link: String, failure: QuicklinkLauncher.Failure
    ) async {
        let symbol = quicklink.iconSymbol ?? Quicklink.sfSymbol
        guard let bundleID = failure.missingApplicationBundleID else {
            await core.showNotice(
                title: "Couldn’t Open \(quicklink.name)",
                message: failure.localizedDescription, symbol: symbol, tone: .danger)
            return
        }
        // The only failure with a usable second option, so it offers it rather than dead-ending.
        let name = applicationName(forBundleID: bundleID) ?? bundleID
        guard
            await core.reportFailure(
                title: "Couldn’t Open \(quicklink.name)",
                message: "\(name) isn’t installed any more.", symbol: symbol,
                recovery: "Open with Default")
        else { return }
        performQuicklinkOpen(quicklink, link: link, forcingDefaultApp: true)
    }

    private func applicationName(forBundleID bundleID: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .flatMap { FileManager.default.displayName(atPath: $0.path) }
    }

    // MARK: - Library

    @discardableResult
    func addQuicklink(_ draft: Quicklink) throws -> Quicklink {
        try store.add(draft)
    }

    func updateQuicklink(_ draft: Quicklink) throws {
        try store.update(draft)
    }

    /// Deletes and unwinds every reference; `confirming: false` is for the pane, which asked.
    func deleteQuicklink(id: UUID, confirming: Bool = true) async {
        guard let quicklink = store.quicklink(id: id) else { return }
        if confirming, settings.quicklinkConfirmsBeforeDelete {
            guard
                await core.confirm(
                    title: "Delete “\(quicklink.name)”?",
                    message: "Its shortcut, favorite slot and learned ranking go with it.",
                    symbol: quicklink.iconSymbol ?? Quicklink.sfSymbol, confirmTitle: "Delete")
            else { return }
        }
        // Unwound only once the row is gone: a failed delete must not strand its references.
        do {
            try store.remove(id: id)
        } catch {
            await core.showNotice(
                title: "Couldn’t Delete “\(quicklink.name)”", message: error.localizedDescription,
                symbol: quicklink.iconSymbol ?? Quicklink.sfSymbol, tone: .danger)
            return
        }
        removeQuicklinkReferences(ids: [id], entryIDs: [quicklink.entryID])
    }

    func toggleQuicklinkPinned(id: UUID) {
        do { try store.togglePinned(id: id) } catch { report(error) }
    }

    func setQuicklinkShowsInRootSearch(_ shows: Bool, id: UUID) {
        do { try store.setShowsInRootSearch(shows, id: id) } catch { report(error) }
    }

    func duplicateQuicklink(id: UUID) {
        do { _ = try store.duplicate(id: id) } catch { report(error) }
    }

    /// Quicklinks are authored data, so a refused write says so rather than reading as a no-op.
    private func report(_ error: QuicklinkError) {
        Task {
            await core.showNotice(
                title: "Couldn’t Save the Change", message: error.localizedDescription,
                symbol: Quicklink.sfSymbol, tone: .danger)
        }
    }

    /// Opens the Quicklinks pane with the editor showing `quicklink`; nil is a new one.
    func editQuicklink(_ quicklink: Quicklink?) {
        core.pendingQuicklinkEdit = QuicklinkEditRequest(quicklink: quicklink)
        settingsCoordinator.showSettings(tab: .quicklinks)
    }

    @discardableResult
    func replaceQuicklinks(_ incoming: [Quicklink]) -> Int {
        let previous = store.quicklinks
        let count = store.replace(with: incoming)
        let liveIDs = Set(store.quicklinks.map(\.id))
        let removed = previous.filter { !liveIDs.contains($0.id) }
        removeQuicklinkReferences(
            ids: Set(removed.map(\.id)), entryIDs: Set(removed.map(\.entryID)))
        return count
    }

    private func removeQuicklinkReferences(ids: Set<UUID>, entryIDs: Set<String>) {
        for id in ids {
            let action = HotKeyAction.quicklink(id: id)
            if hotKeys.recordingAction == action { hotKeys.recordingAction = nil }
            hotKeys.setBinding(nil, for: action)
        }
        favorites.remove(keys: entryIDs)
        visibility.removeItemKeys(entryIDs)
        aliases.removeKeys(entryIDs)
        for entryID in entryIDs {
            ranking.reset(itemKey: entryID)
        }
    }

    // MARK: - Import & export

    func exportQuicklinks() async {
        guard !store.quicklinks.isEmpty else {
            await core.showNotice(
                title: "Nothing to Export", message: "You haven’t created any quicklinks yet.",
                symbol: Quicklink.sfSymbol, tone: .neutral)
            return
        }
        guard let url = BackupActions.chooseSaveLocation(named: "Tinycast-Quicklinks") else {
            return
        }
        do {
            try QuicklinkArchive.encode(store.quicklinks).write(to: url, options: .atomic)
            core.showMessage("Exported \(store.quicklinks.count) Quicklinks")
        } catch {
            await core.showNotice(
                title: "Export Failed", message: error.localizedDescription,
                symbol: Quicklink.sfSymbol, tone: .danger)
        }
    }

    func importQuicklinks() async {
        guard let url = BackupActions.chooseJSONFile() else { return }
        do {
            let incoming = try QuicklinkArchive.decode(Data(contentsOf: url))
            let merge = QuicklinkArchive.merge(incoming, into: store.quicklinks)
            let added = store.append(merge.additions)
            // Everything offered was already here, so say so rather than "0 imported".
            guard !added.isEmpty else {
                await core.showNotice(
                    title: "Nothing to Import",
                    message: "Every quicklink in this file is already in your library.",
                    symbol: Quicklink.sfSymbol, tone: .neutral)
                return
            }
            let skipped = merge.skipped + (merge.additions.count - added.count)
            let summary =
                skipped == 0
                ? "Imported \(added.count) quicklinks."
                : "Imported \(added.count) quicklinks. Skipped \(skipped) already in your library."
            await core.showNotice(
                title: "Quicklinks Imported", message: summary, symbol: Quicklink.sfSymbol,
                tone: .success)
        } catch {
            await core.showNotice(
                title: "Import Failed", message: error.localizedDescription,
                symbol: Quicklink.sfSymbol, tone: .danger)
        }
    }
}
