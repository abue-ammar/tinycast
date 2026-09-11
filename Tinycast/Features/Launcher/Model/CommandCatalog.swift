import Foundation

enum CommandCatalog {
    /// Sorted by name for the `AppIndex` invariant; the URL is a placeholder.
    nonisolated static let all: [AppEntry] =
        CommandID.allCases
        .filter { !$0.isQueryDriven }
        .map { makeEntry($0) }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    nonisolated static func entries(ownedBy owner: SettingsTab) -> [AppEntry] {
        owner.ownedCommands.map { makeEntry($0) }
    }

    static func command(for entry: AppEntry) -> CommandID? {
        CommandID(rawValue: entry.id)
    }

    /// From the catalog, not `AppIndex`: a disabled feature's command is absent from the index.
    static func entry(for command: CommandID) -> AppEntry? {
        all.first { $0.id == command.rawValue }
    }

    /// A query-driven row answers one query, so learning or pinning it would misrank a URL.
    static func isQueryDriven(_ entry: AppEntry) -> Bool {
        command(for: entry)?.isQueryDriven ?? false
    }

    /// The row a typed web address earns; unlike a catalog entry, its URL is the real destination.
    static func openInBrowser(for query: String) -> AppEntry? {
        guard case .web(let url)? = QuicklinkDestination.detect(query) else { return nil }
        return makeEntry(.openInBrowser, url: url, subtitle: "URL")
    }

    /// A command's row, built rather than looked up — `all` holds none of the query-driven ones.
    nonisolated static func makeEntry(
        _ id: CommandID, url: URL? = nil, subtitle: String? = nil
    ) -> AppEntry {
        AppEntry(
            id: id.rawValue, name: id.name, url: url ?? placeholderURL(id), bundleID: nil,
            kind: id.entryKind, settingsOwner: id.owner, subtitle: subtitle)
    }

    nonisolated private static func placeholderURL(_ id: CommandID) -> URL {
        URL(string: "tinycast://" + id.rawValue.replacingOccurrences(of: ":", with: "/"))!
    }
}

/// The commands a pane lists itself; its own switch, not `Enable Commands`, decides they exist.
extension SettingsTab {
    var ownedCommands: [CommandID] {
        switch self {
        case .quicklinks:
            [.createQuicklink, .searchQuicklinks, .importQuicklinks, .exportQuicklinks]
        case .ai: [.aiChat]
        case .quickActions: [.fixGrammar, .rewrite, .translate, .summarize]
        case .fileSearch: [.searchFiles]
        case .notes: [.showNotes, .createNote, .searchNotes]
        case .snippets: [.searchSnippets, .createSnippet]
        case .navigation: [.switchWindows, .searchMenuItems]
        case .windowManagement: [.createWindowLayout, .captureWindowLayout]
        case .clipboard: [.clipboardHistory]
        case .emoji: [.searchEmoji]
        case .calendar:
            [.joinNextMeeting, .mySchedule, .createEvent, .copyMeetingLink, .openInCalendar]
        default: []
        }
    }
}

extension CommandID {
    /// The pane that lists this command's controls; nil leaves it to Settings › Commands.
    var owner: SettingsTab? { Self.owners[self] }

    nonisolated private static let owners: [CommandID: SettingsTab] =
        SettingsTab.allCases.reduce(into: [:]) { table, tab in
            for command in tab.ownedCommands { table[command] = tab }
        }

    var entryKind: AppEntry.Kind {
        builtInQuickAction == nil ? .command : .quickAction
    }
}
