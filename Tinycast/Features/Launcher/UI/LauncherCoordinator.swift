import AppKit

/// Owns launcher activation: the one funnel from a palette row to whatever the entry's kind runs.
@MainActor
final class LauncherCoordinator {
    private let ranking: LauncherRankingStore
    private let windowController: PaletteWindowController
    private let paletteCoordinator: PaletteCoordinator
    private let settingsCoordinator: SettingsCoordinator
    private let customCommandCoordinator: CustomCommandCoordinator
    private let systemActionCoordinator: SystemActionCoordinator
    private let quicklinkCoordinator: QuicklinkCoordinator
    private let windowCommandCoordinator: WindowCommandCoordinator
    private let snippetCoordinator: SnippetCoordinator
    private let fileSearchCoordinator: FileSearchCoordinator
    private let notesCoordinator: NotesCoordinator
    private let extensionCoordinator: ExtensionCoordinator
    private let calendarCoordinator: CalendarCoordinator
    /// The backup commands only, which need the live stores to gather from and apply to.
    private unowned let core: AppCore

    init(
        ranking: LauncherRankingStore,
        windowController: PaletteWindowController,
        paletteCoordinator: PaletteCoordinator,
        settingsCoordinator: SettingsCoordinator,
        customCommandCoordinator: CustomCommandCoordinator,
        systemActionCoordinator: SystemActionCoordinator,
        quicklinkCoordinator: QuicklinkCoordinator,
        windowCommandCoordinator: WindowCommandCoordinator,
        snippetCoordinator: SnippetCoordinator,
        fileSearchCoordinator: FileSearchCoordinator,
        notesCoordinator: NotesCoordinator,
        extensionCoordinator: ExtensionCoordinator,
        calendarCoordinator: CalendarCoordinator,
        core: AppCore
    ) {
        self.ranking = ranking
        self.windowController = windowController
        self.paletteCoordinator = paletteCoordinator
        self.settingsCoordinator = settingsCoordinator
        self.customCommandCoordinator = customCommandCoordinator
        self.systemActionCoordinator = systemActionCoordinator
        self.quicklinkCoordinator = quicklinkCoordinator
        self.windowCommandCoordinator = windowCommandCoordinator
        self.snippetCoordinator = snippetCoordinator
        self.fileSearchCoordinator = fileSearchCoordinator
        self.notesCoordinator = notesCoordinator
        self.extensionCoordinator = extensionCoordinator
        self.calendarCoordinator = calendarCoordinator
        self.core = core
    }

    // MARK: - Activation

    func launch(
        _ app: AppEntry, searchQuery: String? = nil, arguments: [String: String] = [:]
    ) {
        // A category listing is no search: learning it would rank the row under "s".
        if let searchQuery, AppEntry.Kind.named(by: searchQuery) == nil,
            !CommandCatalog.isQueryDriven(app)
        {
            ranking.record(itemKey: app.preferenceKey, query: searchQuery)
        }
        // Commands dispatch before the palette hides: mode-switching commands keep it open.
        if app.kind == .command {
            runCommand(app)
            return
        }
        if app.kind == .customCommand {
            guard let id = CustomCommand.id(fromEntryID: app.id) else { return }
            customCommandCoordinator.runCustomCommand(id: id)
            return
        }
        if app.kind == .systemAction {
            guard let action = SystemActionCatalog.action(forEntryID: app.id) else { return }
            systemActionCoordinator.runSystemAction(id: action.id)
            return
        }
        if app.kind == .windowCommand {
            guard let command = WindowCommandCatalog.command(forEntryID: app.id) else { return }
            windowCommandCoordinator.runWindowCommand(id: command.id)
            return
        }
        // Before the palette hides: a view command takes the palette over rather than closing it.
        if app.kind == .extensionCommand {
            extensionCoordinator.runExtensionCommand(app, arguments: arguments)
            return
        }
        if app.kind == .meeting {
            guard let id = MeetingEvent.id(fromEntryID: app.id) else { return }
            calendarCoordinator.activateMeeting(id: id)
            return
        }
        // Before the palette hides: an unfilled quicklink stays up to ask first.
        if app.kind == .quicklink {
            guard let id = Quicklink.id(fromEntryID: app.id) else { return }
            quicklinkCoordinator.openQuicklink(id: id)
            return
        }
        let previous = windowController.previousApp
        paletteCoordinator.hidePalette(restoreFocus: false)
        switch app.kind {
        case .application:
            AppLauncher.launch(app.url)
        case .systemSettings:
            guard let bundleID = app.bundleID else { return }
            AppLauncher.openSettingsPane(bundleID: bundleID)
        case .snippet:
            let snippetID = String(app.id.dropFirst("snippet:".count))
            snippetCoordinator.expandSnippet(id: snippetID, targetApp: previous)
        case .command, .customCommand, .systemAction, .windowCommand, .quicklink,
            .extensionCommand, .meeting:
            break  // handled above
        }
    }

    private func runCommand(_ entry: AppEntry) {
        switch CommandCatalog.command(for: entry) {
        case .aiChat:
            core.aiChatCoordinator.showChat()
        case .fixGrammar:
            core.quickActionCoordinator.run(.fixGrammar)
        case .rewrite:
            core.quickActionCoordinator.run(.rewrite)
        case .translate:
            core.quickActionCoordinator.run(.translate)
        case .summarize:
            core.quickActionCoordinator.run(.summarize)
        case .calculatorHistory:
            paletteCoordinator.showPalette(mode: .calculatorHistory)
        case .clipboardHistory:
            paletteCoordinator.showPalette(mode: .clipboard)
        case .searchEmoji:
            paletteCoordinator.showPalette(mode: .emoji)
        case .searchFiles:
            fileSearchCoordinator.show()
        case .openInBrowser:
            paletteCoordinator.hidePalette(restoreFocus: false)
            AppLauncher.open(entry.url)
        case .runShellCommand:
            break  // Only ever a fallback row, which carries the query this funnel does not have.
        case .joinNextMeeting:
            calendarCoordinator.joinNextMeeting()
        case .copyMeetingLink:
            calendarCoordinator.copyNextMeetingLink()
        case .mySchedule:
            calendarCoordinator.showSchedule()
        case .openInCalendar:
            calendarCoordinator.openNextMeetingInCalendar()
        case .createEvent:
            calendarCoordinator.createEvent()
        case .showNotes:
            paletteCoordinator.hidePalette(restoreFocus: false)
            notesCoordinator.show()
        case .createNote:
            paletteCoordinator.hidePalette(restoreFocus: false)
            notesCoordinator.createNote()
        case .searchNotes:
            paletteCoordinator.hidePalette(restoreFocus: false)
            notesCoordinator.searchNotes()
        case .searchQuicklinks:
            paletteCoordinator.showPalette(mode: .quicklinks)
        case .searchSnippets:
            snippetCoordinator.showSnippets()
        case .createSnippet:
            paletteCoordinator.hidePalette(restoreFocus: false)
            snippetCoordinator.editSnippet(nil)
        case .createQuicklink:
            paletteCoordinator.hidePalette(restoreFocus: false)
            quicklinkCoordinator.editQuicklink(nil)
        case .importQuicklinks:
            paletteCoordinator.hidePalette(restoreFocus: false)
            Task { await quicklinkCoordinator.importQuicklinks() }
        case .exportQuicklinks:
            paletteCoordinator.hidePalette(restoreFocus: false)
            Task { await quicklinkCoordinator.exportQuicklinks() }
        case .exportSettings:
            paletteCoordinator.hidePalette(restoreFocus: false)
            Task { await BackupActions.exportSettings(core: core) }
        case .importSettings:
            paletteCoordinator.hidePalette(restoreFocus: false)
            Task { await BackupActions.importSettings(core: core) }
        case .importFromRaycast:
            paletteCoordinator.hidePalette(restoreFocus: false)
            settingsCoordinator.showBackupSettings()
        case .checkForUpdates:
            paletteCoordinator.hidePalette(restoreFocus: false)
            core.updateCoordinator.checkForUpdates()
        case .settings:
            paletteCoordinator.hidePalette(restoreFocus: false)
            settingsCoordinator.showSettings()
        case .about:
            paletteCoordinator.hidePalette(restoreFocus: false)
            settingsCoordinator.showAbout()
        case .support:
            paletteCoordinator.hidePalette(restoreFocus: false)
            core.supportCoordinator.showSupport()
        case .quit:
            NSApp.terminate(nil)
        case nil:
            break
        }
    }

    // MARK: - Row actions

    func resetRanking(for app: AppEntry) {
        ranking.reset(itemKey: app.preferenceKey)
    }

    func showInFinder(_ app: AppEntry) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(app.url)
    }

    /// Focus is never handed back: the relaunch takes it, or the app that refused has it.
    func restart(_ app: AppEntry) {
        guard app.kind == .application, let bundleID = app.bundleID else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        Task { await AppLauncher.restart(bundleID: bundleID, url: app.url) }
    }

    /// Quits the app behind an entry; a no-op (palette stays put) when it isn't running.
    func quit(_ app: AppEntry) {
        guard app.kind == .application, let bundleID = app.bundleID else { return }
        // Nothing here takes focus, so hand it back unless that app is on its way out.
        let quittingPreviousApp = windowController.previousApp?.bundleIdentifier == bundleID
        guard AppLauncher.quit(bundleID: bundleID) else { return }
        paletteCoordinator.hidePalette(restoreFocus: !quittingPreviousApp)
    }
}
