import AppKit

@MainActor
@Observable
final class QuicklinkCoordinator {
    private(set) var editor: QuicklinkEditorSession?
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
    /// `{clipboard offset=N}` reads the history a snippet expansion does; one owner, one depth.
    private let clipboardHistory: @MainActor () -> [String]
    /// Dialogs and the HUD stay owned by the composition root.
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
        self.clipboardHistory = clipboardHistory
        self.core = core
    }

    // MARK: - Feature presence

    /// Either switch off means the feature reaches the launcher not at all — rows and commands.
    func applyQuicklinksPresence() {
        if !settings.quicklinksEnabled, core.palette.mode == .quicklinkEditor {
            cancelQuicklinkEditing()
        }
        let visible = settings.quicklinksEnabled && settings.quicklinksShowInLauncher
        appIndex.setQuicklinks(visible ? store.quicklinks : [])
        let commands: Set<CommandID> = [
            .createQuicklink, .searchQuicklinks, .importQuicklinks, .exportQuicklinks
        ]
        appIndex.setCommandsVisible(commands, settings.quicklinksEnabled)
        appIndex.setCommandsListed(commands, settings.quicklinksShowInLauncher)
    }

    // MARK: - Opening

    /// `values` are the header's argument fields; anything missing sends the row back to them.
    func openQuicklink(
        id: UUID, forcingDefaultApp: Bool = false, values: [String: String] = [:]
    ) {
        guard let quicklink = openableQuicklink(id: id) else { return }
        open(makeAttempt(quicklink, values: values, forcingDefaultApp: forcingDefaultApp))
    }

    /// The only entry that seeds an argument from the selection.
    func openQuicklinkFromHotKey(id: UUID) {
        guard let quicklink = openableQuicklink(id: id) else { return }
        let attempt = makeAttempt(quicklink, values: [:], forcingDefaultApp: false)
        guard let argument = selectedTextArgument(for: quicklink) else { return open(attempt) }
        guard attempt.context.selection.isEmpty, let app = attempt.copySource else {
            return open(attempt.filling(argument))
        }
        Task {
            guard let copied = await copyingSelection(into: attempt, from: app) else { return }
            open(copied.filling(argument))
        }
    }

    /// The fallback row's query, which fills the first `{argument}` the link still owes.
    func openQuicklink(id: UUID, filling seed: String) {
        guard let quicklink = store.quicklink(id: id) else { return }
        let arguments = SnippetTemplateEngine.declaredArguments(in: quicklink.link)
        guard let target = arguments.first(where: { !$0.isOptional }) ?? arguments.first else {
            return openQuicklink(id: id)
        }
        openQuicklink(id: id, values: [target.name: seed])
    }

    private func openableQuicklink(id: UUID) -> Quicklink? {
        guard settings.quicklinksEnabled, let quicklink = store.quicklink(id: id),
            quicklink.isEnabled
        else { return nil }
        return quicklink
    }

    private struct OpenAttempt {
        var quicklink: Quicklink
        var context: SnippetTemplateEngine.ExpansionContext
        /// Where a ⌘C may still read the selection from; nil once one has been tried.
        var copySource: NSRunningApplication?
        var values: [String: String]
        var forcingDefaultApp: Bool

        func filling(_ argument: String) -> OpenAttempt {
            let text = context.selection.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return self }
            var attempt = self
            attempt.values[argument] = text
            return attempt
        }
    }

    private func makeAttempt(
        _ quicklink: Quicklink, values: [String: String], forcingDefaultApp: Bool
    ) -> OpenAttempt {
        // With the palette closed a shortcut still reads the selection from wherever the caret is.
        let target =
            windowController.isVisible
            ? windowController.previousTarget : InjectionTarget.current()
        return OpenAttempt(
            quicklink: quicklink,
            context: injector.captureExpansionContext(
                target: target, clipboardHistory: clipboardHistory()),
            copySource: target?.externalApp, values: values, forcingDefaultApp: forcingDefaultApp)
    }

    private func selectedTextArgument(for quicklink: Quicklink) -> String? {
        guard settings.quicklinkPassesSelectedText,
            let first = SnippetTemplateEngine.declaredArguments(in: quicklink.link).first,
            first.options.isEmpty
        else { return nil }
        return first.name
    }

    /// Every open ends here, so neither missing values nor an empty selection can be bypassed.
    private func open(_ attempt: OpenAttempt) {
        var attempt = attempt
        let quicklink = attempt.quicklink
        let encoding: SnippetTemplateEngine.ValueEncoding =
            QuicklinkDestination.usesURLEncoding(quicklink.link) ? .percentEncoding : .none
        // The override outlives the trip through the fields, so it is honoured on the way back.
        attempt.forcingDefaultApp =
            attempt.forcingDefaultApp || pendingDefaultAppOverride == quicklink.id
        let expansion = SnippetTemplateEngine.expand(
            text: quicklink.link, context: attempt.context, userArguments: attempt.values,
            encoding: encoding)
        guard expansion.missingArguments.isEmpty else {
            pendingDefaultAppOverride = attempt.forcingDefaultApp ? quicklink.id : nil
            promptForArguments(quicklink, values: attempt.values)
            return
        }
        pendingDefaultAppOverride = nil
        guard expansion.readsSelection, attempt.context.selection.isEmpty else {
            performQuicklinkOpen(
                quicklink, link: expansion.text, forcingDefaultApp: attempt.forcingDefaultApp)
            return
        }
        // An empty `{selection}` fails rather than opening a search for nothing.
        guard let app = attempt.copySource else { return reportMissingSelection() }
        Task {
            guard let copied = await copyingSelection(into: attempt, from: app) else { return }
            open(copied)
        }
    }

    private func copyingSelection(
        into attempt: OpenAttempt, from app: NSRunningApplication
    ) async -> OpenAttempt? {
        // The palette holds key, so the ⌘C would land in its own search field.
        if windowController.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
        var attempt = attempt
        attempt.context.selection = await injector.copySelection(from: app) ?? ""
        attempt.copySource = nil
        guard let quicklink = openableQuicklink(id: attempt.quicklink.id) else { return nil }
        attempt.quicklink = quicklink
        return attempt
    }

    private func reportMissingSelection() {
        core.showMessage(
            Permissions.isAccessibilityTrusted()
                ? "Couldn’t get the selected text"
                : "Allow Tinycast to use Accessibility in System Settings",
            tone: .danger)
    }

    /// Search Quicklinks is the one argument surface, so a shortcut missing values lands there.
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

    func deleteQuicklink(id: UUID, alwaysConfirm: Bool = false) async {
        guard let quicklink = store.quicklink(id: id) else { return }
        if alwaysConfirm || settings.quicklinkConfirmsBeforeDelete {
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

    /// Keeps the row and its shortcut, but takes it out of every surface that could open it.
    func setQuicklinkEnabled(_ enabled: Bool, id: UUID) {
        do { try store.setEnabled(enabled, id: id) } catch { report(error) }
    }

    func copyQuicklink(id: UUID) {
        guard let quicklink = openableQuicklink(id: id) else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        guard Paster.copyPlainText(quicklink.link) else {
            core.showMessage("Couldn’t copy link")
            return
        }
        core.showMessage("Link copied")
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

    func editQuicklink(_ quicklink: Quicklink?) {
        guard settings.quicklinksEnabled else { return }
        editor = QuicklinkEditorSession(quicklink: quicklink)
        paletteCoordinator.showPalette(mode: .quicklinkEditor)
    }

    func saveQuicklink() {
        guard settings.quicklinksEnabled, let editor, editor.canSave else { return }
        do {
            var draft = editor.draft(now: Date())
            if editor.original == nil {
                try addQuicklink(draft)
            } else {
                guard let current = store.quicklink(id: draft.id) else {
                    editor.errorMessage = "This quicklink was deleted. Copy your changes before closing."
                    return
                }
                draft.isEnabled = current.isEnabled
                try updateQuicklink(draft)
            }
            cancelQuicklinkEditing()
        } catch {
            editor.errorMessage = error.localizedDescription
        }
    }

    func cancelQuicklinkEditing() {
        guard core.palette.mode == .quicklinkEditor else { return }
        if !core.palette.pop(preservingSelection: true) {
            paletteCoordinator.hidePalette()
            core.palette.prepare(mode: .launcher)
        }
        editor = nil
    }

    func editorDidClose(_ editor: QuicklinkEditorSession) {
        if self.editor === editor { self.editor = nil }
    }

    /// Revealing needs a real path, which a template lacks until it expands.
    static func revealablePath(of quicklink: Quicklink) -> String? {
        guard !QuicklinkDestination.containsPlaceholder(quicklink.link),
            case .path(let path)? = QuicklinkDestination.detect(quicklink.link)
        else { return nil }
        return path
    }

    /// False for a link that names no file or folder, leaving ⌘F unhandled.
    @discardableResult
    func showQuicklinkInFinder(_ quicklink: Quicklink) -> Bool {
        guard let path = Self.revealablePath(of: quicklink) else { return false }
        paletteCoordinator.hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(URL(fileURLWithPath: path))
        return true
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
                    title: "Nothing to Import",
                    message: "Every quicklink in this file is already in your library.",
                    symbol: Quicklink.sfSymbol, tone: .neutral)
                return
            }
            let skipped = incoming.count - added.count
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
