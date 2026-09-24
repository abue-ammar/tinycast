import AppKit

struct AppEntry: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case application
        case systemSettings
        case command
        case quickAction
        case customCommand
        case snippet
        case systemAction
        case windowCommand
        case windowLayout
        case quicklink
        case appleShortcut
        case extensionCommand
        case meeting

        var descriptor: KindDescriptor {
            switch self {
            case .application:
                return KindDescriptor(
                    label: "Application", sectionTitle: "Applications",
                    openVerb: "Open Application", canHideFromSearch: true,
                    canRevealInFinder: true, canDragOut: true, isSymbolIcon: false, rankPriority: 4)
            case .systemSettings:
                return KindDescriptor(
                    label: "System Setting", sectionTitle: "System Settings",
                    openVerb: "Open System Setting", canHideFromSearch: true,
                    canRevealInFinder: true, canDragOut: false, isSymbolIcon: false, rankPriority: 1)
            case .command:
                return KindDescriptor(
                    label: "Command", sectionTitle: "Commands",
                    openVerb: "Run Command", canHideFromSearch: true,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 3)
            case .quickAction:
                return KindDescriptor(
                    label: "Quick Action", sectionTitle: "Quick Actions",
                    openVerb: "Run Quick Action", canHideFromSearch: true,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 3)
            case .customCommand:
                return KindDescriptor(
                    label: "Custom Command", sectionTitle: "Custom Commands",
                    openVerb: "Run Custom Command", canHideFromSearch: false,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 3)
            case .snippet:
                return KindDescriptor(
                    label: "Snippet", sectionTitle: "Snippets",
                    openVerb: "Paste Snippet", canHideFromSearch: false,
                    canRevealInFinder: true, canDragOut: false, isSymbolIcon: true, rankPriority: 3)
            case .systemAction:
                return KindDescriptor(
                    label: "System Action", sectionTitle: "System Actions",
                    openVerb: "Run System Action", canHideFromSearch: true,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 3)
            case .windowCommand:
                return KindDescriptor(
                    label: "Window Command", sectionTitle: "Window Management",
                    openVerb: "Move Window", canHideFromSearch: true,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 3)
            case .windowLayout:
                return KindDescriptor(
                    label: "Window Layout", sectionTitle: "Window Layouts",
                    openVerb: "Arrange Windows", canHideFromSearch: true,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 3)
            case .quicklink:
                return KindDescriptor(
                    label: "Quicklink", sectionTitle: "Quicklinks",
                    openVerb: "Open Quicklink", canHideFromSearch: false,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 2)
            case .appleShortcut:
                // File-backed so every row draws the Shortcuts app's own icon.
                return KindDescriptor(
                    label: "Apple Shortcut", sectionTitle: "Apple Shortcuts",
                    openVerb: "Run Shortcut", canHideFromSearch: true,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: false, rankPriority: 3)
            case .extensionCommand:
                // The label is per-entry, the owning extension's title; this is the fallback.
                return KindDescriptor(
                    label: "Extension", sectionTitle: "Extensions",
                    openVerb: "Run Command", canHideFromSearch: true,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 3)
            case .meeting:
                return KindDescriptor(
                    label: "Meeting", sectionTitle: "Meetings",
                    openVerb: "Join Meeting", canHideFromSearch: false,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 1)
            }
        }
    }

    /// Fixed per kind: a new `Kind` case fails to build until it names every field.
    struct KindDescriptor: Sendable {
        let label: String
        let sectionTitle: String
        let openVerb: String
        /// Only where Settings lists a per-item checkbox to put it back: a hide is never one-way.
        let canHideFromSearch: Bool
        let canRevealInFinder: Bool
        /// Only an application: a pane or a shortcut dropped on another app opens nothing there.
        let canDragOut: Bool
        let isSymbolIcon: Bool
        /// Breaks a full tie, apps first: Calculator over Calculator History.
        let rankPriority: Int
    }

    let id: String  // file path (or "command:…" id) — always unique
    let name: String  // clean display name, never includes ".app"
    let url: URL
    let bundleID: String?
    let kind: Kind
    /// Set when a feature pane, not this entry's category pane, lists its controls and gates it.
    var settingsOwner: SettingsTab?
    /// Secondary label beside the name, for an entry whose name alone can't say what it acts on.
    var subtitle: String?
    /// Background-refresh dot for a scheduled extension command; nil everywhere else.
    var backgroundRefresh: ExtensionRefreshState?
    /// Ranked like the name: a translation, a rename, `CFBundleAlternateNames`.
    var alternateTitles: [String] = []
    /// Per-item symbol, for the one kind whose glyph is the user's choice. Nil elsewhere.
    var symbolName: String?
    /// Found by, never ranked by: a declared name, an extension's keywords.
    var keywords: [String] = []
    /// Moves when the bundle's icon changes on disk, retiring the cached bitmap. Applications only.
    var iconStamp: Int = 0
    /// Set by the feature that produced the entry when its glyph isn't derivable from `kind`.
    var iconOverride: EntryIcon?
    /// What this entry comes from — an extension's title. Labels the row; ranks as a subtitle.
    var ownerName: String?
    /// When it landed on disk, so a fresh install can be suggested before its first open.
    var installedAt: Date?
    /// The searchable form of every field above, built at publish by `buildSearchProfile`.
    var search = SearchProfile.unnamed

    /// Stable identity for learned ranking, favorites, and other per-entry preferences.
    var preferenceKey: String { bundleID ?? id }

    /// What this entry is called, in the shape `EntryNaming` reads.
    var naming: EntryNaming.Sources {
        var sources = EntryNaming.Sources(name: name)
        sources.alternateTitles = alternateTitles
        // The subtitle a row prints wins; the owner it replaced still finds the entry.
        sources.subtitle = subtitle ?? ownerName
        sources.keywords = keywords + (subtitle == nil ? [] : [ownerName].compactMap { $0 })
        return sources
    }

    /// Built once per index change, never per keystroke; only `AppIndex.named` calls it.
    mutating func buildSearchProfile() { search = EntryNaming.profile(for: naming) }

    /// Only a name the entry lacks adds anything; a bundle usually spells itself the same twice.
    mutating func addAlternateTitle(_ candidate: String) {
        let existing = [name] + alternateTitles
        guard !candidate.isEmpty,
            !existing.contains(where: {
                FuzzyMatch.normalized($0) == FuzzyMatch.normalized(candidate)
            })
        else { return }
        alternateTitles.append(candidate)
    }

    var kindLabel: String { ownerName ?? kind.descriptor.label }

    /// The hotkey action for this entry, or nil when the entry has no addressable action.
    var hotKeyAction: HotKeyAction? {
        switch kind {
        case .command:
            return CommandCatalog.command(for: self)?.hotKeyAction
        case .quickAction:
            if let command = CommandCatalog.command(for: self) { return command.hotKeyAction }
            return CustomQuickAction.id(fromEntryID: id).map { .quickAction(id: $0) }
        case .application:
            return bundleID.map { .app(bundleID: $0) }
        case .systemSettings:
            return bundleID.map { .settingsPane(bundleID: $0) }
        case .customCommand:
            return CustomCommand.id(fromEntryID: id).map { .customCommand(id: $0) }
        case .systemAction:
            return SystemActionCatalog.action(forEntryID: id).map { .systemAction(id: $0.id) }
        case .windowCommand:
            if let command = WindowCommandCatalog.command(forEntryID: id) {
                return .windowCommand(id: command.id)
            }
            return CustomWindowSize.id(fromEntryID: id).map { .customWindowSize(id: $0) }
        case .windowLayout:
            return WindowLayout.id(fromEntryID: id).map { .windowLayout(id: $0) }
        case .quicklink:
            return Quicklink.id(fromEntryID: id).map { .quicklink(id: $0) }
        case .appleShortcut:
            return AppleShortcut.id(fromEntryID: id).map { .appleShortcut(id: $0) }
        case .snippet, .extensionCommand, .meeting:
            return nil
        }
    }

    /// Synthetic entries have no file to reveal; a destination is its record's own action.
    var canRevealInFinder: Bool { kind.descriptor.canRevealInFinder }

    var canHideFromSearch: Bool { kind.descriptor.canHideFromSearch }

    var canDragOut: Bool { kind.descriptor.canDragOut }

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
        case .quickAction:
            return CommandCatalog.command(for: self)?.sfSymbol ?? CustomQuickAction.sfSymbol
        case .systemAction: return SystemActionCatalog.action(forEntryID: id)?.sfSymbol ?? "questionmark"
        case .windowCommand:
            return WindowCommandCatalog.command(forEntryID: id)?.sfSymbol
                ?? CustomWindowSize.sfSymbol
        case .windowLayout: return WindowLayout.sfSymbol
        case .meeting: return "video.fill"
        case .application, .systemSettings, .appleShortcut, .extensionCommand: return "questionmark"
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

    /// A custom size shares the window commands' kind and section, as custom Quick Actions do.
    init(_ size: CustomWindowSize) {
        self.init(
            id: size.entryID, name: size.name,
            url: URL(string: "tinycast://window-size/" + size.id.uuidString)!,
            bundleID: nil, kind: .windowCommand)
    }

    /// The one row a custom Quick Action draws, wherever it is offered from.
    init(_ action: CustomQuickAction) {
        self.init(
            id: action.entryID, name: action.name,
            url: URL(string: "tinycast://quick-action/" + action.id.uuidString)!,
            bundleID: nil, kind: .quickAction, symbolName: action.iconSymbol)
    }

    /// The one row a custom command draws, wherever it is offered from.
    init(_ command: CustomCommand) {
        self.init(
            id: command.entryID, name: command.name,
            url: URL(string: "tinycast://custom-command/" + command.id.uuidString)!,
            bundleID: nil, kind: .customCommand, symbolName: command.iconSymbol)
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

    /// No bundle id: that would key every shortcut's alias and ranking to the Shortcuts app.
    init(_ shortcut: AppleShortcut, applicationURL: URL) {
        self.init(
            id: shortcut.entryID, name: shortcut.name, url: applicationURL, bundleID: nil,
            kind: .appleShortcut)
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

    /// The launcher's rows in order, with the size of each pinned section at their head.
    struct Results: Equatable {
        var entries: [AppEntry] = []
        var favoriteCount = 0
        var suggestionCount = 0
    }

    private struct MatchKey: Equatable {
        let query: String
        let entriesRevision: Int
        let rankingRevision: Int
        let aliasRevision: Int
        let sensitivity: SearchSensitivity
    }

    private struct ResultsKey: Equatable {
        let match: MatchKey
        let visibilityRevision: Int
        let favoritesRevision: Int
        let hotKeysRevision: Int
        let showsSuggestions: Bool
        /// Suggestions and usage order age with the clock, which no revision tracks.
        let minute: Int
    }

    /// Repeated renders for the same query reuse the ranking instead of re-matching every frame.
    @ObservationIgnored private var matchMemo = Memo<MatchKey, [AppEntry]>()
    @ObservationIgnored private var resultsMemo = Memo<ResultsKey, Results>()
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
    private var customWindowSizeEntries: [AppEntry] = []
    private var windowLayoutEntries: [AppEntry] = []
    private var quicklinkEntries: [AppEntry] = []
    private var appleShortcutEntries: [AppEntry] = []
    private var customQuickActionEntries: [AppEntry] = []
    private var extensionEntries: [AppEntry] = []
    private var meetingEntries: [AppEntry] = []
    /// The catalog's commands a disabled feature hides; the Commands slice is recomputed from it.
    private var hiddenCommands: Set<CommandID> = []
    /// Kept out of launcher search by a "Show in launcher" switch, yet still runnable by shortcut.
    private var unlistedCommands: Set<CommandID> = []
    private var nameCache = BundleNameCache()
    private var paneCache: SettingsPaneScanner.Cache?
    private var isRefreshing = false
    /// Set when a refresh lands mid-scan, so a scope edit is never silently dropped.
    private var refreshPending = false
    private let ranking: LauncherRankingStore
    private let aliases: AliasStore
    private var settings: AppSettings?
    /// Fired after every scan, even an unchanged one: LaunchServices can trail a deletion by seconds.
    @ObservationIgnored var onScan: (() -> Void)?

    init(ranking: LauncherRankingStore, aliases: AliasStore) {
        self.ranking = ranking
        self.aliases = aliases
    }

    /// The always-relevant built-ins, plus whatever a disabled feature has not hidden.
    private var commandEntries: [AppEntry] {
        visibleCatalogEntries.filter { $0.kind == .command }
    }

    private var quickActionEntries: [AppEntry] {
        visibleCatalogEntries.filter { $0.kind == .quickAction } + customQuickActionEntries
    }

    private var visibleCatalogEntries: [AppEntry] {
        CommandCatalog.all.filter {
            guard let command = CommandCatalog.command(for: $0) else { return true }
            return !hiddenCommands.contains(command) && !unlistedCommands.contains(command)
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

    func setCommandsListed(_ commands: Set<CommandID>, _ listed: Bool) {
        let updated =
            listed ? unlistedCommands.subtracting(commands) : unlistedCommands.union(commands)
        guard updated != unlistedCommands else { return }
        unlistedCommands = updated
        publishEntries()
    }

    /// Replaces the command slice without rescanning, so Settings edits land at once.
    func setCustomCommands(_ commands: [CustomCommand]) {
        let entries = commands.filter(\.isEnabled).map(AppEntry.init)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard entries != customCommandEntries else { return }
        customCommandEntries = entries
        publishEntries()
    }

    /// Replaces the custom Quick Action slice, which shares its section with the shipped four.
    func setCustomQuickActions(_ actions: [CustomQuickAction]) {
        let entries = actions.sorted(by: CustomQuickAction.precedes).map(AppEntry.init)
        guard entries != customQuickActionEntries else { return }
        customQuickActionEntries = entries
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

    /// Discovered from the Shortcuts app, so it arrives already built and sorted.
    func setAppleShortcuts(_ entries: [AppEntry]) {
        guard entries != appleShortcutEntries else { return }
        appleShortcutEntries = entries
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

    /// Replaces the custom-size slice, which shares its section with the window commands.
    func setCustomWindowSizes(_ sizes: [CustomWindowSize]) {
        let entries = sizes.sorted(by: CustomWindowSize.precedes).map(AppEntry.init)
        guard entries != customWindowSizeEntries else { return }
        customWindowSizeEntries = entries
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
                    alternateTitles: [record.snippet.keyword].compactMap { $0 })
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
                AppIndex.scan(
                    scopes: scopes, languages: languages, cache: reusing, paneCache: reusingPanes)
            }.value
            nameCache = cache
            paneCache = panes
            guard found != discoveredEntries else { continue }
            discoveredEntries = found
            publishEntries()
        } while refreshPending
        onScan?()
    }

    /// Out of the index *and* unknown to LaunchServices, so dropping a search scope isn't a delete.
    func isUninstalled(bundleID: String) -> Bool {
        !discoveredEntries.contains { $0.kind == .application && $0.bundleID == bundleID }
            && NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) == nil
    }

    nonisolated private static func scan(
        scopes: [String], languages: [String], cache: BundleNameCache,
        paneCache: SettingsPaneScanner.Cache?
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
                    result[first].addAlternateTitle(fileName)
                    continue
                }

                // Finder's rule: LaunchServices ignores a display name the file name contradicts.
                let names = cache.names(
                    for: url, base: fileName, developmentRegion: bundle?.developmentLocalization)
                // Raw: Calendar's strings file swaps its `iCal` array for a name.
                let alternates = bundle?.infoDictionary?["CFBundleAlternateNames"] as? [String] ?? []
                // Still searchable, never the label: `code` must keep finding Visual Studio Code.
                let declared = [bundle?.installedAppName].compactMap { $0 }
                var entry = AppEntry(
                    id: url.path, name: names.first ?? fileName, url: url, bundleID: bundleID,
                    kind: .application, alternateTitles: Array(names.dropFirst()) + alternates,
                    keywords: declared, iconStamp: FileIconStamp.value(for: url),
                    installedAt: try? url.resourceValues(forKeys: [.addedToDirectoryDateKey])
                        .addedToDirectoryDate)
                entry.addAlternateTitle(fileName)
                if let bundleID { indexByBundleID[bundleID] = result.count }
                result.append(entry)
            }
            // Slice order is section order, so the flat selection maps 1:1 onto rows.
            let apps = result.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            // Settings panes are `.appex` bundles, which carry no Spotlight alternate names.
            let (panes, panesCache) = SettingsPaneScanner.scan(languages: languages, cache: paneCache)
            // Named here, not at publish: romanizing a CJK index is ~50 ms of main-actor time.
            return (AppIndex.named(apps + panes), cache, panesCache)
        }
    }

    /// The searchable form of every name an entry carries. `scan` names the app slice itself.
    nonisolated private static func named(_ entries: [AppEntry]) -> [AppEntry] {
        entries.map { entry in
            var entry = entry
            entry.buildSearchProfile()
            return entry
        }
    }

    private func publishEntries() {
        // Each slice arrives in its own display order; the slice order is the section order.
        let updated =
            Self.named(meetingEntries) + discoveredEntries
            + Self.named(
                extensionEntries + quicklinkEntries + appleShortcutEntries + snippetEntries
                    + Self.systemActionEntries + windowLayoutEntries + windowCommandEntries
                    + customWindowSizeEntries + customCommandEntries + quickActionEntries
                    + commandEntries)
        guard updated != apps else { return }
        apps = updated
        entriesRevision &+= 1
    }

    /// Ranked matches, or a whole category when the query names one. Empty returns the full list.
    func matches(_ query: String, limit: Int = 200) -> [AppEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return apps }
        return matchMemo.value(for: matchKey(q)) {
            guard let kind = AppEntry.Kind.named(by: q) else { return rank(q, limit: limit) }
            return categoryListing(kind, query: q)
        }
    }

    /// Slice order is section order, so filtering keeps sections and selection aligned.
    private func categoryListing(_ kind: AppEntry.Kind, query: String) -> [AppEntry] {
        let listed = apps.filter {
            $0.kind == kind || FuzzyMatch.normalized($0.name) == FuzzyMatch.normalized(query)
        }
        return byUsage(listed, usage: ranking.snapshot())
    }

    /// The launcher's rows: ranked matches, or favorites, suggestions and each kind by usage.
    func orderedResults(
        query: String, visibility: VisibilityStore, favorites: FavoritesStore, hotKeys: HotKeyManager
    ) -> Results {
        let q = query.trimmingCharacters(in: .whitespaces)
        let showsSuggestions = settings?.launcherShowsSuggestions ?? true
        let usage = ranking.snapshot()
        let key = ResultsKey(
            match: matchKey(q), visibilityRevision: visibility.revision,
            favoritesRevision: favorites.revision, hotKeysRevision: hotKeys.revision,
            showsSuggestions: showsSuggestions, minute: Int(usage.now.timeIntervalSince1970 / 60))
        return resultsMemo.value(for: key) {
            // Filtering stays downstream of `matches` so that memo is never keyed on hidden state.
            let visible = matches(q).filter(visibility.isVisible)
            guard q.isEmpty else { return Results(entries: visible) }
            let split = favorites.ordered(visible)
            let suggested =
                showsSuggestions ? suggestions(from: split.rest, usage: usage, hotKeys: hotKeys) : []
            let shown = Set(suggested.map(\.id))
            let rest = byUsage(split.rest.filter { !shown.contains($0.id) }, usage: usage)
            return Results(
                entries: split.favorites + suggested + rest, favoriteCount: split.favorites.count,
                suggestionCount: suggested.count)
        }
    }

    private var sensitivity: SearchSensitivity { settings?.rootSearchSensitivity ?? .default }

    private func matchKey(_ query: String) -> MatchKey {
        MatchKey(
            query: query, entriesRevision: entriesRevision, rankingRevision: ranking.revision,
            aliasRevision: aliases.revision, sensitivity: sensitivity)
    }

    private func rank(_ q: String, limit: Int) -> [AppEntry] {
        Signposts.interval("AppIndex.rank") {
            let usage = ranking.snapshot()
            return LauncherOrder.ranked(
                apps, query: LauncherOrder.Query(q), sensitivity: sensitivity, limit: limit,
                profile: \.search, signals: { self.signals(for: $0, usage: usage) })
        }
    }

    /// Each kind's run sorted by usage; the runs keep publication order, which is section order.
    private func byUsage(_ entries: [AppEntry], usage: LauncherRankingStore.Snapshot) -> [AppEntry] {
        var ordered: [AppEntry] = []
        ordered.reserveCapacity(entries.count)
        var start = entries.startIndex
        while start < entries.endIndex {
            let kind = entries[start].kind
            let end = entries[start...].firstIndex { $0.kind != kind } ?? entries.endIndex
            ordered += LauncherOrder.byUsage(
                Array(entries[start..<end]), signals: { self.signals(for: $0, usage: usage) })
            start = end
        }
        return ordered
    }

    /// Meetings keep their own card, AI is never pushed, and Tinycast opening Tinycast goes nowhere.
    private func suggestions(
        from entries: [AppEntry], usage: LauncherRankingStore.Snapshot, hotKeys: HotKeyManager
    ) -> [AppEntry] {
        let eligible = entries.filter {
            $0.kind != .meeting && $0.settingsOwner != .ai
                && !($0.bundleID?.hasPrefix(Self.ownBundlePrefix) ?? false)
        }
        return LauncherSuggestions.select(from: eligible, now: usage.now) { entry in
            // `hotKeyAction` is nil for an extension command, whose shortcut is keyed by entry ID.
            let action: HotKeyAction? =
                entry.kind == .extensionCommand ? .extensionCommand(entryID: entry.id) : entry.hotKeyAction
            return LauncherSuggestions.Traits(
                signals: signals(for: entry, usage: usage), installedAt: entry.installedAt,
                hasHotKey: action.flatMap(hotKeys.binding(for:)) != nil,
                priority: CommandCatalog.command(for: entry)?.suggestionPriority)
        }
    }

    private static let ownBundlePrefix = "com.tinycast."

    private func signals(
        for entry: AppEntry, usage: LauncherRankingStore.Snapshot
    ) -> LauncherOrder.Signals {
        LauncherOrder.Signals(
            alias: aliases.alias(for: entry.preferenceKey).map { SearchText($0, transliterated: false) },
            usage: usage.usage(for: entry.preferenceKey),
            priority: entry.kind.descriptor.rankPriority, title: entry.name,
            boostedTerms: CommandCatalog.command(for: entry)?.boostedTerms ?? [])
    }
}
