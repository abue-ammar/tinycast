import AppKit

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

    /// Stable identity for learned ranking, favorites, and other per-entry preferences.
    var preferenceKey: String { bundleID ?? id }

    var kindLabel: String {
        switch kind {
        case .application: return "Application"
        case .systemSettings: return "System Setting"
        case .command: return "Command"
        case .snippet: return "Snippet"
        }
    }

    /// The global-hotkey action that opens this entry, or `nil` when it has no bundle ID to key the binding on.
    var hotKeyAction: HotKeyAction? {
        guard let bundleID else { return nil }
        switch kind {
        case .application: return .app(bundleID: bundleID)
        case .systemSettings: return .settingsPane(bundleID: bundleID)
        case .command, .snippet: return nil
        }
    }

    /// Command entries draw an SF Symbol tile; everything else uses its file icon.
    var isSymbolIcon: Bool { kind == .command || kind == .snippet }
    var symbolIconName: String {
        if kind == .snippet { return "text.quote" }
        return CommandRegistry.command(for: self)?.sfSymbol ?? "questionmark"
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

    /// One-entry memo so repeated renders for the same query reuse the ranking instead of re-matching every frame.
    private var matchCache: (query: String, rankingRevision: Int, result: [AppEntry])?

    private var isRefreshing = false
    private let ranking: LauncherRankingStore

    init(ranking: LauncherRankingStore) {
        self.ranking = ranking
    }

    /// Re-scan (called on every launcher open); the in-flight guard drops overlapping reopens and `apps` is only re-published when the set changed, so an unchanged reopen does no UI work.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let found = await Task.detached(priority: .utility) { AppIndex.scan() }.value
        guard found != apps else { return }
        apps = found
        matchCache = nil
    }

    nonisolated private static func scan() -> [AppEntry] {
        let fm = FileManager.default
        var searchDirs = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
        ].map { URL(fileURLWithPath: $0) }
        searchDirs.append(fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications"))

        var seenBundleIDs = Set<String>()
        var result: [AppEntry] = []
        for dir in searchDirs {
            guard
                let items = try? fm.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
                )
            else { continue }
            for url in items where url.pathExtension == "app" {
                let bundle = Bundle(url: url)
                let bundleID = bundle?.bundleIdentifier
                // Dedup by bundle id; first directory (/Applications) wins.
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
        }
        // Apps, then Settings panes, then Snippets, then Commands — the sectioned launcher relies on this order so its flat selection index maps 1:1 onto rows.
        let apps = result.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return apps + SettingsPaneScanner.scan() + scanSnippets() + CommandRegistry.all
    }

    nonisolated private static func scanSnippets() -> [AppEntry] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let snippetsDir = home.appendingPathComponent(".config/tinycast/snippets", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: snippetsDir, includingPropertiesForKeys: nil) else {
            return []
        }
        var entries: [AppEntry] = []
        for url in files where url.pathExtension.lowercased() == "md" {
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                let snippet = SnippetMarkdownSerializer.parse(content: content, fileURL: url)
                if snippet.isEnabled && snippet.showInLauncher {
                    entries.append(
                        AppEntry(
                            // The file path, not `snippet.id`: the serializer never persists the UUID, so it is freshly minted on every scan and cannot key learned ranking, favorites or visibility.
                            id: "snippet:\(url.path)",
                            name: snippet.name,
                            url: url,
                            bundleID: nil,
                            kind: .snippet
                        )
                    )
                }
            }
        }
        return entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
        let snippets = AppCore.shared.snippetsStore.snippets
        let scored = apps.compactMap { app -> (AppEntry, Int)? in
            var bestScore = FuzzyMatch.score(query: q, candidate: app.name)
            // A snippet is reachable by keyword or category too; the keyword edges out a bare name hit of the same kind.
            if app.kind == .snippet,
                let snippet = snippets.first(where: {
                    "snippet:\($0.id.uuidString)" == app.id || $0.name == app.name
                })
            {
                if let kw = snippet.keyword, !kw.isEmpty,
                    let kwScore = FuzzyMatch.score(query: q, candidate: kw)
                {
                    bestScore = max(bestScore ?? -1, kwScore + 200)
                }
                if let cat = snippet.category, !cat.isEmpty,
                    let catScore = FuzzyMatch.score(query: q, candidate: cat)
                {
                    bestScore = max(bestScore ?? -1, catScore)
                }
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
