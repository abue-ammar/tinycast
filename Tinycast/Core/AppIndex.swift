import AppKit
import Combine

struct AppEntry: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case application
        case systemSettings
        case command
        case snippet
    }

    let id: String  // file path (or "command:…" id) — always unique
    let name: String  // clean display name, never includes ".app"
    let url: URL
    let bundleID: String?
    let kind: Kind
    /// Extra strings this entry also matches on in search — a snippet's keyword and category. Empty for every other kind.
    var matchAliases: [String] = []

    /// Stable identity for learned ranking, favorites, and other per-entry preferences.
    var preferenceKey: String { bundleID ?? id }

    var kindLabel: String {
        switch kind {
        case .application: return "Application"
        case .systemSettings: return "System Setting"
        case .command:
            return CustomCommand.id(fromEntryID: id) == nil ? "Command" : "Custom Command"
        case .snippet: return "Snippet"
        }
    }

    /// The global-hotkey action for this entry, or `nil` for built-in commands and unaddressable bundles.
    var hotKeyAction: HotKeyAction? {
        switch kind {
        case .application:
            return bundleID.map { .app(bundleID: $0) }
        case .systemSettings:
            return bundleID.map { .settingsPane(bundleID: $0) }
        case .command:
            return CustomCommand.id(fromEntryID: id).map { .customCommand(id: $0) }
        case .snippet:
            return nil
        }
    }

    /// Command entries are synthetic — no file behind them to reveal.
    var canRevealInFinder: Bool { kind != .command }

    /// Command and snippet entries draw an SF Symbol tile; everything else uses its file icon.
    var isSymbolIcon: Bool { kind == .command || kind == .snippet }
    var symbolIconName: String {
        if kind == .snippet { return "text.quote" }
        if let builtIn = CommandRegistry.command(for: self) { return builtIn.sfSymbol }
        return CustomCommand.id(fromEntryID: id) == nil ? "questionmark" : "terminal"
    }

    var icon: NSImage {
        isSymbolIcon
            ? IconCache.symbolIcon(named: symbolIconName) : IconCache.icon(forFile: url.path)
    }
}

/// Caches app icons by file path, downsampled to a small fixed bitmap and byte-bounded, so list rows don't re-hit `NSWorkspace` or balloon memory.
enum IconCache {
    /// `NSCache` is thread-safe but not `Sendable`, so a detached decode populating what the main actor reads needs the guarantee asserted once here.
    private final class Cache: NSCache<NSString, NSImage>, @unchecked Sendable {}

    // 48pt (2× Retina) is plenty for the ≤24pt draw size, and keeping each icon small caps launcher memory since a scrolled `LazyVStack` pins every row's icon.
    private static let displayPixel: CGFloat = 48

    private static let cache: Cache = {
        let cache = Cache()
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    /// Cache-only lookups (never decode) so a row can paint an already-warm icon on the same frame.
    static func cached(forFile path: String) -> NSImage? { cache.object(forKey: path as NSString) }
    static func cachedSymbol(named name: String) -> NSImage? {
        cache.object(forKey: ("symbol:" + name) as NSString)
    }

    /// A freshly-decoded, thereafter-immutable `NSImage` is safe to move across the actor boundary.
    private struct Decoded: @unchecked Sendable { let image: NSImage? }

    /// Return the decode directly (not a cache re-read) so an `NSCache` purge mid-decode can't strand a row on its placeholder. A missing path returns nil — not `NSWorkspace`'s broken-document icon — and never caches, so an uninstalled app can't leave a broken icon behind.
    static func loadAsync(forFile path: String) async -> NSImage? {
        if let cached = cached(forFile: path) { return cached }
        return await Task.detached(priority: .userInitiated) { () -> Decoded in
            guard FileManager.default.fileExists(atPath: path) else { return Decoded(image: nil) }
            return Decoded(image: icon(forFile: path))
        }.value.image
    }
    static func loadSymbolAsync(named name: String) async -> NSImage? {
        if let cached = cachedSymbol(named: name) { return cached }
        return await Task.detached(priority: .userInitiated) {
            Decoded(image: symbolIcon(named: name))
        }.value.image
    }

    static func icon(forFile path: String) -> NSImage {
        let key = path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let (icon, cost) = downsampled(NSWorkspace.shared.icon(forFile: path))
        cache.setObject(icon, forKey: key, cost: cost)
        return icon
    }

    /// Command "icons": an SF Symbol on a rounded tile, in the same bitmap shape as app icons so rows treat every entry identically.
    static func symbolIcon(named name: String) -> NSImage {
        let key = "symbol:" + name as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let side = displayPixel
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            // Tile inset mirrors the margin macOS app icons carry inside their canvas.
            let tile = NSRect(x: 0, y: 0, width: side, height: side).insetBy(dx: 4, dy: 4)
            NSColor.white.withAlphaComponent(0.09).setFill()
            NSBezierPath(roundedRect: tile, xRadius: 9, yRadius: 9).fill()

            let config = NSImage.SymbolConfiguration(pointSize: 21, weight: .medium)
                .applying(.init(paletteColors: [.white.withAlphaComponent(0.85)]))
            guard
                let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                    .withSymbolConfiguration(config)
            else { return true }
            let size = symbol.size
            symbol.draw(
                in: NSRect(
                    x: (side - size.width) / 2, y: (side - size.height) / 2,
                    width: size.width, height: size.height))
            return true
        }
        let (icon, cost) = downsampled(image)
        cache.setObject(icon, forKey: key, cost: cost)
        return icon
    }

    /// Rasterize the multi-rep workspace icon into one `displayPixel`-square bitmap, returning it and its decoded byte cost.
    private static func downsampled(_ source: NSImage) -> (NSImage, Int) {
        // Fixed 2× (not `NSScreen.main`, which is main-thread-only) so this can rasterize on a detached decode; 96px covers the ≤24pt draw on any display.
        let pixels = Int(displayPixel * 2)
        let fallbackCost = Int(displayPixel * displayPixel * 4)
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0)
        else { return (source, fallbackCost) }
        rep.size = NSSize(width: displayPixel, height: displayPixel)
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            return (source, fallbackCost)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: rep.size))
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return (image, rep.bytesPerRow * rep.pixelsHigh)
    }
}

@MainActor
final class AppIndex: ObservableObject {
    @Published private(set) var apps: [AppEntry] = []

    private var snippetEntries: [AppEntry] = []

    /// One-entry memo so repeated renders for the same query reuse the ranking instead of re-matching every frame.
    private var matchCache: (query: String, rankingRevision: Int, result: [AppEntry])?

    private var discoveredEntries: [AppEntry] = []
    private var customCommandEntries: [AppEntry] = []
    private var isRefreshing = false
    /// Set when a refresh is requested mid-scan, so a scope edit landing during an in-flight scan isn't silently dropped.
    private var refreshPending = false
    private let ranking: LauncherRankingStore
    private var settings: AppSettings?
    private var cancellables: Set<AnyCancellable> = []

    init(ranking: LauncherRankingStore) {
        self.ranking = ranking
    }

    /// Replaces the user-authored command slice without rescanning disk so Settings edits reach launcher search immediately.
    func setCustomCommands(_ commands: [CustomCommand]) {
        let entries = commands.map { command in
            AppEntry(
                id: command.entryID, name: command.name,
                url: URL(string: "tinycast://custom-command/" + command.id.uuidString)!,
                bundleID: nil, kind: .command)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard entries != customCommandEntries else { return }
        customCommandEntries = entries
        publishEntries()
    }

    func updateSnippets(_ records: [StoredSnippet]) {
        let entries = records
            .filter { $0.snippet.isEnabled && $0.snippet.showInLauncher }
            .map { record in
                AppEntry(
                    id: "snippet:\(record.id)",
                    name: record.snippet.name,
                    url: record.fileURL,
                    bundleID: nil,
                    kind: .snippet,
                    matchAliases: [record.snippet.keyword, record.snippet.category]
                        .compactMap { $0 })
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard entries != snippetEntries else { return }
        snippetEntries = entries
        publishEntries()
    }

    /// Wires the search scopes, re-indexing when the user edits them so Settings changes land without waiting for the next launcher open.
    func start(settings: AppSettings) {
        self.settings = settings
        settings.$searchScopes
            .dropFirst()
            // @Published emits synchronously on the main actor (hence assumeIsolated), before the property is written, so the scan is deferred to a task that reads the settled value.
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    Task { await self.refresh() }
                }
            }
            .store(in: &cancellables)
    }

    /// Re-scan (called on every launcher open); overlapping reopens collapse into one trailing scan and `apps` is only re-published when the set changed, so an unchanged reopen does no UI work.
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
            let found = await Task.detached(priority: .utility) { AppIndex.scan(scopes: scopes) }
                .value
            guard found != discoveredEntries else { continue }
            discoveredEntries = found
            publishEntries()
        } while refreshPending
    }

    nonisolated private static func scan(scopes: [String]) -> [AppEntry] {
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
            result.append(
                AppEntry(
                    id: url.path, name: name, url: url, bundleID: bundleID,
                    kind: .application))
        }
        // `publishEntries` appends snippets and commands after apps and Settings panes so the sectioned flat selection maps 1:1 onto rows.
        let apps = result.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return apps + SettingsPaneScanner.scan()
    }

    private func publishEntries() {
        let commands = (CommandRegistry.all + customCommandEntries).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        let updated = discoveredEntries + snippetEntries + commands
        guard updated != apps else { return }
        apps = updated
        matchCache = nil
    }

    /// Ranked matches. Empty query returns the full alphabetical list.
    func matches(_ query: String, limit: Int = 200) -> [AppEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return apps }
        if let matchCache, matchCache.query == q,
            matchCache.rankingRevision == ranking.revision
        {
            return matchCache.result
        }
        let result = rank(q, limit: limit)
        matchCache = (q, ranking.revision, result)
        return result
    }

    private func rank(_ q: String, limit: Int) -> [AppEntry] {
        let learned = ranking.boosts(query: q)
        let scored = apps.compactMap { app -> (AppEntry, Int)? in
            // An entry matches on its name or on any alias it carries (snippet keyword, category), whichever scores best — all inside the same tiers, so an alias can never outrank a better name match.
            var bestScore = FuzzyMatch.score(query: q, candidate: app.name)
            for candidate in app.matchAliases {
                guard let aliasScore = FuzzyMatch.score(query: q, candidate: candidate) else { continue }
                bestScore = max(bestScore ?? aliasScore, aliasScore)
            }
            guard let score = bestScore else { return nil }
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

enum FuzzyMatch {
    /// Tiered relevance score (higher is better), or nil when the query doesn't match; tiers are spaced so a better kind always wins.
    static func score(query: String, candidate: String) -> Int? {
        let q = normalized(query)
        let c = normalized(candidate)
        guard !q.isEmpty else { return 0 }

        if c == q { return 100_000 }
        if c.hasPrefix(q) { return 90_000 - c.count }

        if let range = c.range(of: q) {
            let atWordStart = isWordStart(c, range.lowerBound)
            return (atWordStart ? 80_000 : 70_000) - c.count
        }

        guard let sub = subsequenceScore(Array(q), Array(c)) else { return nil }
        return sub
    }

    /// App metadata can contain invisible bidirectional/zero-width format scalars (WhatsApp's display name starts with U+200E); they must not demote an otherwise-visible prefix match.
    private static func normalized(_ value: String) -> String {
        let scalars = value.unicodeScalars.filter {
            $0.properties.generalCategory != .format
        }
        return String(String.UnicodeScalarView(scalars)).lowercased()
    }

    private static func isWordStart(_ s: String, _ index: String.Index) -> Bool {
        if index == s.startIndex { return true }
        let before = s[s.index(before: index)]
        return !before.isLetter && !before.isNumber
    }

    /// Subsequence match with bonuses for consecutive hits and word boundaries, or nil when `q` isn't a subsequence of `c`.
    private static func subsequenceScore(_ q: [Character], _ c: [Character]) -> Int? {
        var qi = 0
        var score = 0
        var run = 0
        var prev = -2
        for (ci, ch) in c.enumerated() where qi < q.count && ch == q[qi] {
            var bonus = 1
            if ci == prev + 1 {
                run += 1
                bonus += run * 3
            } else {
                run = 0
            }
            if ci == 0 {
                bonus += 12
            } else {
                let before = c[ci - 1]
                if !before.isLetter && !before.isNumber { bonus += 8 }
            }
            score += bonus
            prev = ci
            qi += 1
        }
        guard qi == q.count else { return nil }
        return score
    }
}
