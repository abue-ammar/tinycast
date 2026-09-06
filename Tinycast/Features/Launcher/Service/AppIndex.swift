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
        case windowLayout
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
            case .windowLayout:
                return KindDescriptor(
                    label: "Window Layout", sectionTitle: "Window Layouts",
                    openVerb: "Arrange Windows", canRevealInFinder: false, isSymbolIcon: true)
            case .quicklink:
                return KindDescriptor(
                    label: "Quicklink", sectionTitle: "Quicklinks",
                    openVerb: "Open Quicklink", canRevealInFinder: false, isSymbolIcon: true)
            case .extensionCommand:
                // The label is per-entry, the owning extension's title; this is the fallback.
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
    /// Secondary label beside the name, for an entry whose name alone can't say what it acts on.
    var subtitle: String?
    /// Other names as strong as the display name: a snippet's keyword, the name in an Info.plist.
    var matchAliases: [String] = []
    /// Per-item symbol, for the one kind whose glyph is the user's choice. Nil elsewhere.
    var symbolName: String?
    /// Other ways to say this entry's name: Spotlight alternates, localizations, romanizations.
    var alternateNames: [String] = []
    /// `CFBundleExecutable`, matched literally as a last resort. Applications only.
    var executableName: String?
    /// Moves when the bundle's icon changes on disk, retiring the cached bitmap. Applications only.
    var iconStamp: Int = 0
    /// Set by the feature that produced the entry when its glyph isn't derivable from `kind`.
    var iconOverride: EntryIcon?
    /// What this entry comes from — an extension's title. Labels the row, and matches weakly.
    var ownerName: String?
    /// The searchable form of every field above, built at publish by `buildAliases`.
    var aliases: [SearchAlias] = []

    /// Stable identity for learned ranking, favorites, and other per-entry preferences.
    var preferenceKey: String { bundleID ?? id }

    /// What this entry is called, in the shape `EntryNaming` reads.
    var naming: EntryNaming.Sources {
        var sources = EntryNaming.Sources(name: name)
        sources.strongNames = matchAliases
        sources.translations = alternateNames
        sources.ownerName = ownerName
        sources.bundleID = bundleID
        sources.executableName = executableName
        return sources
    }

    /// Built once per index change, never per keystroke; only `AppIndex.named` calls it.
    mutating func buildAliases() { aliases = EntryNaming.aliases(for: naming) }

    /// Only a name the entry lacks adds anything; a bundle usually spells itself the same twice.
    mutating func addStrongName(_ candidate: String) {
        let existing = [name] + matchAliases
        guard !candidate.isEmpty,
            !existing.contains(where: {
                FuzzyMatch.normalized($0) == FuzzyMatch.normalized(candidate)
            })
        else { return }
        matchAliases.append(candidate)
    }

    var kindLabel: String { ownerName ?? kind.descriptor.label }

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
        case .windowLayout:
            return WindowLayout.id(fromEntryID: id).map { .windowLayout(id: $0) }
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
        guard kind.descriptor.isSymbolIcon else { return .file(stamp: iconStamp) }
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
        case .windowLayout: return WindowLayout.sfSymbol
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

extension AppEntry {
    /// The one row a layout draws, wherever it is offered from.
    init(_ layout: WindowLayout) {
        self.init(
            id: layout.entryID, name: layout.name,
            url: URL(string: "tinycast://window-layout/" + layout.id.uuidString)!,
            bundleID: nil, kind: .windowLayout, symbolName: layout.iconSymbol)
    }

    /// The one row a quicklink draws, wherever it is offered from.
    init(_ quicklink: Quicklink) {
        self.init(
            id: quicklink.entryID, name: quicklink.name,
            url: URL(string: "tinycast://quicklink/" + quicklink.id.uuidString)!,
            bundleID: nil, kind: .quicklink,
            symbolName: quicklink.iconSymbol
                ?? QuicklinkDestination.detect(quicklink.link)?.defaultSymbol)
    }
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
    private var windowLayoutEntries: [AppEntry] = []
    private var quicklinkEntries: [AppEntry] = []
    private var extensionEntries: [AppEntry] = []
    private var meetingEntries: [AppEntry] = []
    /// The catalog's commands a disabled feature hides; the Commands slice is recomputed from it.
    private var hiddenCommands: Set<CommandID> = []
    private var nameCache = BundleNameCache()
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

    /// Whether the feature behind a command is on, which is what its shortcut has to obey too.
    func isCommandEnabled(_ command: CommandID) -> Bool {
        !hiddenCommands.contains(command)
    }

    /// A feature's commands leave the Commands slice when it is off; `visible` restores them.
    func setCommandsVisible(_ commands: Set<CommandID>, _ visible: Bool) {
        let updated = visible ? hiddenCommands.subtracting(commands) : hiddenCommands.union(commands)
        guard updated != hiddenCommands else { return }
        hiddenCommands = updated
        publishEntries()
    }

    /// Replaces the command slice without rescanning, so Settings edits land at once.
    func setCustomCommands(_ commands: [CustomCommand]) {
        let entries = commands.filter(\.isEnabled).map { command in
            AppEntry(
                id: command.entryID, name: command.name,
                url: URL(string: "tinycast://custom-command/" + command.id.uuidString)!,
                bundleID: nil, kind: .customCommand, symbolName: command.iconSymbol)
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
            .filter { $0.isEnabled && $0.showsInRootSearch }
            .sorted(by: Quicklink.precedes)
            .map(AppEntry.init)
        guard entries != quicklinkEntries else { return }
        quicklinkEntries = entries
        publishEntries()
    }

    /// Events move on their own, so this comes from the store's change hook, not an edit.
    func setMeetings(_ entries: [AppEntry]) {
        guard entries != meetingEntries else { return }
        meetingEntries = entries
        publishEntries()
    }

    /// Called by `ExtensionManager` when the installed set or a chosen appearance changes.
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

    /// Replaces the layout slice; a toggle can't split its entries from their section.
    func setWindowLayouts(_ layouts: [WindowLayout]) {
        let entries = layouts.sorted(by: WindowLayout.precedes).map(AppEntry.init)
        guard entries != windowLayoutEntries else { return }
        windowLayoutEntries = entries
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
            let reusingPanes = paneCache
            let languages = BundleLocalization.indexedLanguages(Locale.preferredLanguages)
            let reusing = BundleNameCache(reusing: nameCache, languages: languages)
            let (found, cache, panes) = await Task.detached(priority: .utility) {
                AppIndex.scan(scopes: scopes, cache: reusing, paneCache: reusingPanes)
            }.value
            nameCache = cache
            paneCache = panes
            guard found != discoveredEntries else { continue }
            discoveredEntries = found
            publishEntries()
        } while refreshPending
    }

    nonisolated private static func scan(
        scopes: [String], cache: BundleNameCache, paneCache: SettingsPaneScanner.Cache?
    ) -> ([AppEntry], BundleNameCache, SettingsPaneScanner.Cache?) {
        Signposts.interval("AppIndex.scan") {
            var cache = cache
            var indexByBundleID: [String: Int] = [:]
            var result: [AppEntry] = []
            for url in SearchScopes.appBundles(in: scopes) {
                let bundle = Bundle(url: url)
                let bundleID = bundle?.bundleIdentifier
                let fileName = EntryNaming.strippingAppExtension(url.lastPathComponent)
                // Dedup by bundle id; the first scope wins, but a renamed copy lends its name.
                if let bundleID, let first = indexByBundleID[bundleID] {
                    result[first].addStrongName(fileName)
                    continue
                }

                let names = cache.names(for: url)
                // Finder's rule: LaunchServices ignores a display name the file name contradicts.
                let name = names.localized.first ?? fileName
                let executable =
                    bundle?.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
                var entry = AppEntry(
                    id: url.path, name: name, url: url, bundleID: bundleID,
                    kind: .application,
                    alternateNames: Array(names.localized.dropFirst()) + names.alternates,
                    executableName: executable, iconStamp: FileIconStamp.value(for: url))
                entry.addStrongName(fileName)
                // Still searchable, never the label: `code` must keep finding Visual Studio Code.
                if let declared = bundle?.installedAppName { entry.addStrongName(declared) }
                if let bundleID { indexByBundleID[bundleID] = result.count }
                result.append(entry)
            }
            // Slice order is section order, so the flat selection maps 1:1 onto rows.
            let apps = result.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            // Settings panes are `.appex` bundles, which carry no Spotlight alternate names.
            let (panes, panesCache) = SettingsPaneScanner.scan(cache: paneCache)
            // Named here, not at publish: romanizing a CJK index is ~50 ms of main-actor time.
            return (AppIndex.named(apps + panes), cache, panesCache)
        }
    }

    /// The searchable form of every name an entry carries. `scan` names the app slice itself.
    nonisolated private static func named(_ entries: [AppEntry]) -> [AppEntry] {
        entries.map { entry in
            var entry = entry
            entry.buildAliases()
            return entry
        }
    }

    private func publishEntries() {
        // Each slice arrives in its own display order; the slice order is the section order.
        let updated =
            Self.named(meetingEntries) + discoveredEntries
            + Self.named(
                extensionEntries + quicklinkEntries + snippetEntries + Self.systemActionEntries
                    + windowLayoutEntries + windowCommandEntries + customCommandEntries
                    + commandEntries)
        guard updated != apps else { return }
        apps = updated
        entriesRevision &+= 1
    }

    /// Ranked matches, or a whole category when the query names one. Empty returns the full list.
    func matches(_ query: String, limit: Int = 200) -> [AppEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        // The opening list stays alphabetical: a list that reorders as you use it is unscannable.
        guard !q.isEmpty else { return apps }
        let key = MatchKey(
            query: q, entriesRevision: entriesRevision, rankingRevision: ranking.revision,
            aliasRevision: aliases.revision)
        return matchMemo.value(for: key) {
            guard let kind = AppEntry.Kind.named(by: q) else { return rank(q, limit: limit) }
            return categoryListing(kind, query: q)
        }
    }

    /// Slice order is section order, so filtering keeps sections and selection aligned.
    private func categoryListing(_ kind: AppEntry.Kind, query: String) -> [AppEntry] {
        apps.filter { $0.kind == kind || FuzzyMatch.normalized($0.name) == FuzzyMatch.normalized(query) }
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
            let learned = ranking.usage(query: q)
            return LauncherOrder.ranked(
                apps, query: FuzzyMatch.Query(q), limit: limit,
                fields: { app in
                    guard let alias = self.aliases.alias(for: app.preferenceKey) else {
                        return SearchFields(app.aliases)
                    }
                    return SearchFields(app.aliases + [.userAlias(alias)])
                },
                usage: { learned[$0.preferenceKey] ?? 0 }, name: \.name)
        }
    }
}
