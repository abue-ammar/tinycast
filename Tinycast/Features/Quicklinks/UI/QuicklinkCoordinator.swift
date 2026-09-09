import AppKit

/// Owns the quicklink flow: the open funnel, the argument prompt, the library and import/export.
@MainActor
final class QuicklinkCoordinator {
    private let store: QuicklinkStore
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let injector: TextInjector
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

    /// The quicklink whose ⌘↵ override must survive the trip to the header's argument fields.
    private var pendingDefaultAppOverride: UUID?

    init(
        store: QuicklinkStore,
        settings: AppSettings,
        appIndex: AppIndex,
        injector: TextInjector,
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

    /// Either switch off means the feature reaches the launcher not at all — rows and commands.
    func applyQuicklinksPresence() {
        let visible = settings.quicklinksEnabled && settings.quicklinksShowInLauncher
        appIndex.setQuicklinks(visible ? store.quicklinks : [])
        appIndex.setCommandsVisible(
            [.createQuicklink, .searchQuicklinks, .importQuicklinks, .exportQuicklinks], visible)
    }

    // MARK: - Opening

    /// The one funnel for every open, so neither the switch nor the missing values can be bypassed.
    /// `values` are the header's argument fields; anything still missing sends the row back to them.
    func openQuicklink(
        id: UUID, forcingDefaultApp: Bool = false, values: [String: String] = [:]
    ) {
        guard settings.quicklinksEnabled, let quicklink = store.quicklink(id: id),
            quicklink.isEnabled
        else { return }
        // With the palette closed a shortcut still reads the selection from the frontmost app.
        let target =
            windowController.isVisible
            ? windowController.previousApp : NSWorkspace.shared.frontmostApplication
        let encoding: SnippetTemplateEngine.ValueEncoding =
            QuicklinkDestination.usesURLEncoding(quicklink.link) ? .percentEncoding : .none
        var context = injector.captureExpansionContext(
            targetApp: target, clipboardHistory: clipboardHistory())

        // An unreadable selection is missing, not empty: substitute the clipboard, or take the field.
        if context.selection.isEmpty, SnippetTemplateEngine.usesSelection(quicklink.link) {
            switch settings.quicklinkSelectionFallback {
            case .clipboard:
                context = context.replacingSelection(with: context.clipboard)
            case .ask:
                let typed = values[Self.selectionArgument.name] ?? ""
                if !typed.isEmpty { context = context.replacingSelection(with: typed) }
            }
        }

        // The override outlives the trip through the fields, so it is honoured on the way back.
        let forcesDefault = forcingDefaultApp || pendingDefaultAppOverride == id
        let expansion = SnippetTemplateEngine.expand(
            text: quicklink.link, context: context, userArguments: values, encoding: encoding)
        guard expansion.missingArguments.isEmpty else {
            pendingDefaultAppOverride = forcesDefault ? id : nil
            promptForArguments(quicklink, values: values)
            return
        }
        pendingDefaultAppOverride = nil
        performQuicklinkOpen(quicklink, link: expansion.text, forcingDefaultApp: forcesDefault)
    }

    /// The fallback row's query, which fills the first `{argument}` the link declares.
    func openQuicklink(id: UUID, filling seed: String) {
        guard let quicklink = store.quicklink(id: id),
            let first = SnippetTemplateEngine.declaredArguments(in: quicklink.link).first
        else { return openQuicklink(id: id) }
        openQuicklink(id: id, values: [first.name: seed])
    }

    /// `{selection}` promoted to a field when unreadable and the setting says ask.
    static let selectionArgument = SnippetTemplateEngine.MissingArgument(
        name: "Selected Text", options: [])

    /// The header fields a row shows: the link's own arguments, plus the one the setting asks for.
    func promptedArguments(for quicklink: Quicklink) -> [SnippetTemplateEngine.MissingArgument] {
        var arguments = SnippetTemplateEngine.declaredArguments(in: quicklink.link)
        // Asked for up front rather than after a failed read: a chip cannot capture a selection.
        if settings.quicklinkSelectionFallback == .ask,
            SnippetTemplateEngine.usesSelection(quicklink.link)
        {
            arguments.append(Self.selectionArgument)
        }
        return arguments
    }

    /// Search Quicklinks is the one argument surface, so a shortcut with values missing lands there.
    private func promptForArguments(_ quicklink: Quicklink, values: [String: String]) {
        paletteCoordinator.showPalette(mode: .quicklinks)
        // After the show: `prepare` runs inside it and would clear everything set beforehand.
        core.palette.selection = store.enabled.firstIndex(of: quicklink) ?? 0
        for (name, value) in values {
            core.palette.commandArguments[PaletteState.argumentKey(quicklink.entryID, name)] = value
        }
        core.palette.pendingArgumentEntryID = quicklink.entryID
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
                title: String(localized: "Couldn’t Open \(quicklink.name)", bundle: .appLanguage),
                message: failure.localizedDescription, symbol: symbol, tone: .danger)
            return
        }
        // The only failure with a usable second option, so it offers it rather than dead-ending.
        let name = applicationName(forBundleID: bundleID) ?? bundleID
        guard
            await core.reportFailure(
                title: String(localized: "Couldn’t Open \(quicklink.name)", bundle: .appLanguage),
                message: String(localized: "\(name) isn’t installed any more.", bundle: .appLanguage), symbol: symbol,
                recovery: String(localized: "Open with Default", bundle: .appLanguage))
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
                    title: String(localized: "Delete “\(quicklink.name)”?", bundle: .appLanguage),
                    message: String(
                        localized: "Its shortcut, favorite slot and learned ranking go with it.",
                        bundle: .appLanguage),
                    symbol: quicklink.iconSymbol ?? Quicklink.sfSymbol, confirmTitle: String(
                        localized: "Delete",
                        bundle: .appLanguage))
            else { return }
        }
        // Unwound only once the row is gone: a failed delete must not strand its references.
        do {
            try store.remove(id: id)
        } catch {
            await core.showNotice(
                title: String(
                    localized: "Couldn’t Delete “\(quicklink.name)”",
                    bundle: .appLanguage), message: error.localizedDescription,
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

    /// Keeps the row and its shortcut, but takes it out of every surface that could open it.
    func setQuicklinkEnabled(_ enabled: Bool, id: UUID) {
        do { try store.setEnabled(enabled, id: id) } catch { report(error) }
    }

    func duplicateQuicklink(id: UUID) {
        do { _ = try store.duplicate(id: id) } catch { report(error) }
    }

    /// Quicklinks are authored data, so a refused write says so rather than reading as a no-op.
    private func report(_ error: QuicklinkError) {
        Task {
            await core.showNotice(
                title: String(localized: "Couldn’t Save the Change", bundle: .appLanguage), message: error.localizedDescription,
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
                title: String(localized: "Nothing to Export", bundle: .appLanguage),
                message: String(localized: "You haven’t created any quicklinks yet.", bundle: .appLanguage),
                symbol: Quicklink.sfSymbol, tone: .neutral)
            return
        }
        guard let url = BackupActions.chooseSaveLocation(named: "Tinycast-Quicklinks") else {
            return
        }
        do {
            try QuicklinkArchive.encode(store.quicklinks).write(to: url, options: .atomic)
            core.showMessage(String(localized: "Exported \(store.quicklinks.count) Quicklinks", bundle: .appLanguage))
        } catch {
            await core.showNotice(
                title: String(localized: "Export Failed", bundle: .appLanguage), message: error.localizedDescription,
                symbol: Quicklink.sfSymbol, tone: .danger)
        }
    }

    /// Merges into the library the way Settings → Import does, so Raycast and JSON share one rule.
    @discardableResult
    func addImportedQuicklinks(_ incoming: [Quicklink]) -> [Quicklink] {
        let merge = QuicklinkArchive.merge(incoming, into: store.quicklinks)
        return store.append(merge.additions)
    }

    func importQuicklinks() async {
        guard let url = BackupActions.chooseJSONFile() else { return }
        do {
            let incoming = try QuicklinkArchive.decode(Data(contentsOf: url))
            let added = addImportedQuicklinks(incoming)
            // Everything offered was already here, so say so rather than "0 imported".
            guard !added.isEmpty else {
                await core.showNotice(
                    title: String(localized: "Nothing to Import", bundle: .appLanguage),
                    message: String(localized: "Every quicklink in this file is already in your library.", bundle: .appLanguage),
                    symbol: Quicklink.sfSymbol, tone: .neutral)
                return
            }
            let skipped = incoming.count - added.count
            let summary =
                skipped == 0
                ? String(localized: "Imported \(added.count) quicklinks.", bundle: .appLanguage)
                : String(
                    localized: "Imported \(added.count) quicklinks. Skipped \(skipped) already in your library.",
                    bundle: .appLanguage)
            await core.showNotice(
                title: String(
                    localized: "Quicklinks Imported",
                    bundle: .appLanguage), message: summary, symbol: Quicklink.sfSymbol,
                tone: .success)
        } catch {
            await core.showNotice(
                title: String(localized: "Import Failed", bundle: .appLanguage), message: error.localizedDescription,
                symbol: Quicklink.sfSymbol, tone: .danger)
        }
    }
}
