import AppKit

struct AppEntry: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case application
        case systemSettings
        case command
        case customCommand
        case snippet
        case systemAction
        case windowCommand
        case quicklink
        case extensionCommand
        case meeting

        var descriptor: KindDescriptor {
            switch self {
            case .application:
                return KindDescriptor(
                    label: "Application", sectionTitle: "Applications",
                    openVerb: "Open Application", canRevealInFinder: true, isSymbolIcon: false)
            case .systemSettings:
                return KindDescriptor(
                    label: "System Setting", sectionTitle: "System Settings",
                    openVerb: "Open System Setting", canRevealInFinder: true, isSymbolIcon: false)
            case .command:
                return KindDescriptor(
                    label: "Command", sectionTitle: "Commands",
                    openVerb: "Run Command", canRevealInFinder: false, isSymbolIcon: true)
            case .customCommand:
                return KindDescriptor(
                    label: "Custom Command", sectionTitle: "Custom Commands",
                    openVerb: "Run Custom Command", canRevealInFinder: false, isSymbolIcon: true)
            case .snippet:
                return KindDescriptor(
                    label: "Snippet", sectionTitle: "Snippets",
                    openVerb: "Paste Snippet", canRevealInFinder: true, isSymbolIcon: true)
            case .systemAction:
                return KindDescriptor(
                    label: "System Action", sectionTitle: "System Actions",
                    openVerb: "Run System Action", canRevealInFinder: false, isSymbolIcon: true)
            case .windowCommand:
                return KindDescriptor(
                    label: "Window Command", sectionTitle: "Window Management",
                    openVerb: "Move Window", canRevealInFinder: false, isSymbolIcon: true)
            case .quicklink:
                return KindDescriptor(
                    label: "Quicklink", sectionTitle: "Quicklinks",
                    openVerb: "Open Quicklink", canRevealInFinder: false, isSymbolIcon: true)
            case .extensionCommand:
                // The label is per-entry (the owning extension's title), so this is only the fallback.
                return KindDescriptor(
                    label: "Extension", sectionTitle: "Extensions",
                    openVerb: "Run Command", canRevealInFinder: false, isSymbolIcon: true)
            case .meeting:
                return KindDescriptor(
                    label: "Meeting", sectionTitle: "Meetings",
                    openVerb: "Join Meeting", canRevealInFinder: false, isSymbolIcon: true)
            }
        }
    }

    /// Everything that is fixed per kind. A new `Kind` case fails to build until it names all five.
    struct KindDescriptor: Sendable {
        let label: String
        let sectionTitle: String
        let openVerb: String
        let canRevealInFinder: Bool
        let isSymbolIcon: Bool
    }

    let id: String  // file path (or "command:…" id) — always unique
    let name: String  // clean display name, never includes ".app"
    let url: URL
    let bundleID: String?
    let kind: Kind
    /// Extra strings matching as strongly as the name; empty for every kind but snippets.
    var matchAliases: [String] = []
    /// Per-item symbol, for the one kind whose glyph is the user's choice. Nil elsewhere.
    var symbolName: String?
    /// Spotlight's `kMDItemAlternateNames`, ranked below the display name. Applications only.
    var alternateNames: [String] = []
    /// `CFBundleExecutable`, matched literally as a last resort. Applications only.
    var executableName: String?
    /// Set by the feature that produced the entry when its glyph isn't derivable from `kind`.
    var iconOverride: EntryIcon?
    /// A per-entry label where the kind's own reads too flat — an extension's title, say.
    var labelOverride: String?

    /// Stable identity for learned ranking, favorites, and other per-entry preferences.
    var preferenceKey: String { bundleID ?? id }

    var searchFields: SearchFields {
        SearchFields(
            names: [name] + matchAliases, alternateNames: alternateNames,
            bundleID: bundleID, executableName: executableName)
    }

    var kindLabel: String { labelOverride ?? kind.descriptor.label }

    /// The hotkey action for this entry, or nil when the entry has no addressable action.
    var hotKeyAction: HotKeyAction? {
        switch kind {
        case .command:
            return CommandCatalog.command(for: self)?.hotKeyAction
        case .application:
            return bundleID.map { .app(bundleID: $0) }
        case .systemSettings:
            return bundleID.map { .settingsPane(bundleID: $0) }
        case .customCommand:
            return CustomCommand.id(fromEntryID: id).map { .customCommand(id: $0) }
        case .systemAction:
            return SystemActionCatalog.action(forEntryID: id).map { .systemAction(id: $0.id) }
        case .windowCommand:
            return WindowCommandCatalog.command(forEntryID: id).map { .windowCommand(id: $0.id) }
        case .quicklink:
            return Quicklink.id(fromEntryID: id).map { .quicklink(id: $0) }
        case .snippet, .extensionCommand, .meeting:
            return nil
        }
    }

    /// Synthetic entries have no file to reveal; a destination is its record's own action.
    var canRevealInFinder: Bool { kind.descriptor.canRevealInFinder }

    /// What this row draws, and the only thing any icon path needs to ask.
    var iconSource: EntryIcon { iconOverride ?? defaultIcon }

    /// Derived from the kind alone: synthetic entries get a symbol tile, everything else its file.
    private var defaultIcon: EntryIcon {
        guard kind.descriptor.isSymbolIcon else { return .file }
        return .symbol(symbolName ?? kindSymbol)
    }

    private var kindSymbol: String {
        switch kind {
        case .quicklink: return Quicklink.sfSymbol
        case .snippet: return "text.quote"
        case .customCommand: return CustomCommand.sfSymbol
        case .command: return CommandCatalog.command(for: self)?.sfSymbol ?? "questionmark"
        case .systemAction: return SystemActionCatalog.action(forEntryID: id)?.sfSymbol ?? "questionmark"
        case .windowCommand:
            return WindowCommandCatalog.command(forEntryID: id)?.sfSymbol ?? "questionmark"
        case .meeting: return "video.fill"
        case .application, .systemSettings, .extensionCommand: return "questionmark"
        }
    }

    /// Main-actor because it subscribes the calling view; every caller is a `body`.
    @MainActor var icon: NSImage {
        IconCache.observeStyle()
        return IconCache.icon(for: iconSource, fileURL: url)
    }

    /// Icon identity for a row's async load: re-skinning changes the glyph while `id` stays put.
    var iconKey: String { "\(id)|\(iconSource)" }
}

extension AppEntry.Kind {
    /// The descriptors' own words, lowercased once, so a keystroke costs a lookup and not a scan.
    private static let byCategoryName: [String: AppEntry.Kind] = allCases.reduce(into: [:]) {
        $0[$1.descriptor.sectionTitle.lowercased()] = $1
        $0[$1.descriptor.label.lowercased()] = $1
    }

    /// The category a query names outright. Exact only — a prefix would take a word from an entry.
    static func named(by query: String) -> AppEntry.Kind? {
        byCategoryName[query.trimmingCharacters(in: .whitespaces).lowercased()]
    }
}

@MainActor
@Observable
final class AppIndex {
    private(set) var apps: [AppEntry] = []

    private var snippetEntries: [AppEntry] = []

    private struct MatchKey: Equatable {
        let query: String
        let entriesRevision: Int
        let rankingRevision: Int
        let aliasRevision: Int
    }

    private struct ResultsKey: Equatable {
        let query: String
        let entriesRevision: Int
        let rankingRevision: Int
        let aliasRevision: Int
        let visibilityRevision: Int
        let favoritesRevision: Int
    }

    /// Repeated renders for the same query reuse the ranking instead of re-matching every frame.
    @ObservationIgnored private var matchMemo = Memo<MatchKey, [AppEntry]>()
    @ObservationIgnored private var resultsMemo = Memo<ResultsKey, [AppEntry]>()
    /// Bumped whenever `apps` changes, so both memos above name the entry set they were built from.
    private var entriesRevision = 0

    private static let systemActionEntries: [AppEntry] = SystemActionCatalog.all
        .map { command in
            AppEntry(
                id: command.entryID, name: command.name,
                url: URL(string: "tinycast://system-action/" + command.id.rawValue)!,
                bundleID: nil, kind: .systemAction)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    private static let allWindowCommandEntries: [AppEntry] = WindowCommandCatalog.all
        .map { command in
            AppEntry(
                id: command.entryID, name: command.name,
                url: URL(string: "tinycast://window-command/" + command.id.rawValue)!,
                bundleID: nil, kind: .windowCommand)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    private var discoveredEntries: [AppEntry] = []
    private var customCommandEntries: [AppEntry] = []
    private var windowCommandEntries: [AppEntry] = []
    private var quicklinkEntries: [AppEntry] = []
    private var extensionEntries: [AppEntry] = []
    private var meetingEntries: [AppEntry] = []
    /// The catalog's commands a disabled feature hides; the Commands slice is recomputed from it.
    private var hiddenCommands: Set<CommandID> = []
    private var alternateNameCache = SpotlightNames.Cache()
    private var paneCache: SettingsPaneScanner.Cache?
    private var isRefreshing = false
    /// Set when a refresh lands mid-scan, so a scope edit is never silently dropped.
    private var refreshPending = false
    private let ranking: LauncherRankingStore
    private let aliases: AliasStore
    private var settings: AppSettings?

    init(ranking: LauncherRankingStore, aliases: AliasStore) {
        self.ranking = ranking
        self.aliases = aliases
    }

    /// The always-relevant built-ins, plus whatever a disabled feature has not hidden.
    private var commandEntries: [AppEntry] {
        CommandCatalog.all.filter {
            guard let command = CommandCatalog.command(for: $0) else { return true }
            return !hiddenCommands.contains(command)
        }
    }

    /// A feature's commands leave the Commands slice when the feature is off; `visible` restores them.
    func setCommandsVisible(_ commands: Set<CommandID>, _ visible: Bool) {
        let updated = visible ? hiddenCommands.subtracting(commands) : hiddenCommands.union(commands)
        guard updated != hiddenCommands else { return }
        hiddenCommands = updated
        publishEntries()
    }

    /// Replaces the command slice without rescanning, so Settings edits land at once.
    func setCustomCommands(_ commands: [CustomCommand]) {
        let entries = commands.map { command in
            AppEntry(
                id: command.entryID, name: command.name,
                url: URL(string: "tinycast://custom-command/" + command.id.uuidString)!,
                bundleID: nil, kind: .customCommand)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard entries != customCommandEntries else { return }
        customCommandEntries = entries
        publishEntries()
    }

    /// Replaces the quicklink slice; a toggle can't split its entries from their section.
    func setQuicklinks(_ quicklinks: [Quicklink]) {
        let entries =
            quicklinks
            .filter(\.showsInRootSearch)
            .sorted(by: Quicklink.precedes)
            .map { quicklink in
                AppEntry(
                    id: quicklink.entryID, name: quicklink.name,
                    url: URL(string: "tinycast://quicklink/" + quicklink.id.uuidString)!,
                    bundleID: nil, kind: .quicklink,
                    symbolName: quicklink.iconSymbol
                        ?? QuicklinkDestination.detect(quicklink.link)?.defaultSymbol)
            }
        guard entries != quicklinkEntries else { return }
        quicklinkEntries = entries
        publishEntries()
    }

    /// Replaces the meeting slice. Events move on their own, so this is called from the store's
    /// change hook rather than from a user edit.
    func setMeetings(_ entries: [AppEntry]) {
        guard entries != meetingEntries else { return }
        meetingEntries = entries
        publishEntries()
    }

    /// Replaces the extension-command slice. Called by `ExtensionManager` whenever the installed set,
    /// or an extension's chosen appearance, changes.
    func setExtensionCommands(_ entries: [AppEntry]) {
        guard entries != extensionEntries else { return }
        extensionEntries = entries
        publishEntries()
    }

    /// Shows or hides the window-command slice; the catalog itself is static.
    func setWindowCommandsVisible(_ visible: Bool) {
        let entries = visible ? Self.allWindowCommandEntries : []
        guard entries != windowCommandEntries else { return }
        windowCommandEntries = entries
        publishEntries()
    }

    func updateSnippets(_ records: [StoredSnippet]) {
        let entries =
            records
            .filter { $0.snippet.isEnabled }
            .map { record in
                AppEntry(
                    id: "snippet:\(record.id)",
                    name: record.snippet.name,
                    url: record.fileURL,
                    bundleID: nil,
                    kind: .snippet,
                    matchAliases: [record.snippet.keyword].compactMap { $0 })
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard entries != snippetEntries else { return }
        snippetEntries = entries
        publishEntries()
    }

    /// Wires the scopes, re-indexing on edit rather than waiting for the next open.
    func start(settings: AppSettings) {
        self.settings = settings
        observeSearchScopes()
    }

    /// Fires synchronously on main before the write lands, so the task re-arms, then rescans.
    private func observeSearchScopes() {
        withObservationTracking {
            _ = settings?.searchScopes
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observeSearchScopes()
                await self.refresh()
            }
        }
    }

    /// Re-scan on every open; reopens collapse, and an unchanged set does no UI work.
    func refresh() async {
        guard !isRefreshing else {
            refreshPending = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshPending = false
            let scopes = settings?.searchScopes ?? SearchScopes.defaults
            let reusing = alternateNameCache
            let reusingPanes = paneCache
            let (found, cache, panes) = await Task.detached(priority: .utility) {
                AppIndex.scan(
                    scopes: scopes, cache: SpotlightNames.Cache(reusing: reusing),
                    paneCache: reusingPanes)
            }.value
            alternateNameCache = cache
            paneCache = panes
            guard found != discoveredEntries else { continue }
            discoveredEntries = found
            publishEntries()
        } while refreshPending
    }

    nonisolated private static func scan(
        scopes: [String], cache: SpotlightNames.Cache, paneCache: SettingsPaneScanner.Cache?
    ) -> ([AppEntry], SpotlightNames.Cache, SettingsPaneScanner.Cache?) {
        Signposts.interval("AppIndex.scan") {
            var cache = cache
            var seenBundleIDs = Set<String>()
            var result: [AppEntry] = []
            for url in SearchScopes.appBundles(in: scopes) {
                let bundle = Bundle(url: url)
                let bundleID = bundle?.bundleIdentifier
                // Dedup by bundle id; the earliest scope wins.
                if let bundleID, !seenBundleIDs.insert(bundleID).inserted { continue }

                let name =
                    (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let executable =
                    bundle?.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
                result.append(
                    AppEntry(
                        id: url.path, name: name, url: url, bundleID: bundleID,
                        kind: .application,
                        alternateNames: cache.alternateNames(for: url, displayName: name),
                        // A binary named after the app adds nothing the display name lacks.
                        executableName: executable.flatMap {
                            $0.caseInsensitiveCompare(name) == .orderedSame ? nil : $0
                        }))
            }
            // Slice order is section order, so the flat selection maps 1:1 onto rows.
            let apps = result.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            // Settings panes are `.appex` bundles, which carry no Spotlight alternate names.
            let (panes, panesCache) = SettingsPaneScanner.scan(cache: paneCache)
            return (apps + panes, cache, panesCache)
        }
    }

    private func publishEntries() {
        // Each slice arrives in its own display order; the slice order is the section order.
        let updated =
            meetingEntries + discoveredEntries + extensionEntries + quicklinkEntries + snippetEntries
            + Self.systemActionEntries + windowCommandEntries + customCommandEntries
            + commandEntries
        guard updated != apps else { return }
        apps = updated
        entriesRevision &+= 1
    }

    /// Ranked matches, or a whole category when the query names one. Empty returns the full list.
    func matches(_ query: String, limit: Int = 200) -> [AppEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return apps }
        let key = MatchKey(
            query: q, entriesRevision: entriesRevision, rankingRevision: ranking.revision,
            aliasRevision: aliases.revision)
        return matchMemo.value(for: key) {
            guard let kind = AppEntry.Kind.named(by: q) else { return rank(q, limit: limit) }
            return categoryListing(kind, query: q)
        }
    }

    /// A whole category, plus any entry the query names outright — `System Settings` is both. Slice
    /// order is section order, so filtering alone keeps the sections and the flat selection aligned.
    private func categoryListing(_ kind: AppEntry.Kind, query: String) -> [AppEntry] {
        apps.filter { $0.kind == kind || $0.name.caseInsensitiveCompare(query) == .orderedSame }
    }

    /// The launcher's ordered list: ranked matches minus hidden entries, favorites pinned first.
    func orderedResults(
        query: String, visibility: VisibilityStore, favorites: FavoritesStore
    ) -> [AppEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let key = ResultsKey(
            query: q, entriesRevision: entriesRevision, rankingRevision: ranking.revision,
            aliasRevision: aliases.revision, visibilityRevision: visibility.revision,
            favoritesRevision: favorites.revision)
        return resultsMemo.value(for: key) {
            // Filtering stays downstream of `matches` so that memo is never keyed on hidden state.
            let base = matches(q).filter(visibility.isVisible)
            guard q.isEmpty, !favorites.keys.isEmpty else { return base }
            let split = favorites.ordered(base)
            return split.favorites + split.rest
        }
    }

    private func rank(_ q: String, limit: Int) -> [AppEntry] {
        Signposts.interval("AppIndex.rank") {
            let learned = ranking.boosts(query: q)
            let scored = apps.compactMap { app -> (AppEntry, Int)? in
                var fields = app.searchFields
                fields.userAlias = aliases.alias(for: app.preferenceKey)
                // Base relevance is the strongest field; the boost is added blind to it.
                guard let score = SearchRelevance.score(query: q, fields: fields) else {
                    return nil
                }
                return (app, score + (learned[app.preferenceKey] ?? 0))
            }
            return
                scored
                .sorted {
                    $0.1 != $1.1
                        ? $0.1 > $1.1
                        : $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending
                }
                .prefix(limit)
                .map(\.0)
        }
    }
}
