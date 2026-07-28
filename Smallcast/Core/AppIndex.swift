import AppKit

struct AppEntry: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case application
        case systemSettings
        case command
        case extensionCommand
    }

    let id: String  // file path (or "command:…" / "extension:…" id) — always unique
    let name: String  // clean display name, never includes ".app"
    let url: URL
    let bundleID: String?
    let kind: Kind
    /// An image file to draw instead of the file icon — an extension's manifest icon.
    var imageIconPath: String? = nil
    /// Replaces the trailing kind label; an extension command shows its extension's title there.
    var kindLabelOverride: String? = nil

    var kindLabel: String {
        if let kindLabelOverride { return kindLabelOverride }
        switch kind {
        case .application: return "Application"
        case .systemSettings: return "System Setting"
        case .command: return "Command"
        case .extensionCommand: return "Extension Command"
        }
    }

    /// The global-hotkey action that opens this entry, or `nil` when it has no bundle ID to key the binding on.
    var hotKeyAction: HotKeyAction? {
        guard let bundleID else { return nil }
        switch kind {
        case .application: return .app(bundleID: bundleID)
        case .systemSettings: return .settingsPane(bundleID: bundleID)
        case .command, .extensionCommand: return nil
        }
    }

    /// Command entries draw an SF Symbol tile; an extension command draws its manifest icon when it
    /// ships one, and falls back to a symbol tile otherwise.
    var isSymbolIcon: Bool { kind == .command || (kind == .extensionCommand && imageIconPath == nil) }
    var symbolIconName: String {
        if kind == .extensionCommand { return "puzzlepiece.extension" }
        return CommandRegistry.command(for: self)?.sfSymbol ?? "questionmark"
    }

    var icon: NSImage {
        if let imageIconPath { return IconCache.imageIcon(atPath: imageIconPath) }
        return isSymbolIcon
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

    static func cachedImage(atPath path: String) -> NSImage? {
        cache.object(forKey: ("image:" + path) as NSString)
    }

    /// An extension list row or Detail markdown can reference a remote image; fetch once, then serve
    /// from the same cache as every other row icon. Failures cache nothing, so a transient error retries
    /// on the next render. `downsample` is off for markdown images, which are drawn much larger than a
    /// row icon.
    static func loadRemoteAsync(_ url: URL, downsample: Bool = true) async -> NSImage? {
        let key = ("image:\(downsample ? "" : "full:")" + url.absoluteString) as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        let decoded = await Task.detached(priority: .userInitiated) {
            Decoded(image: NSImage(data: data))
        }.value
        guard let source = decoded.image else { return nil }
        guard downsample else {
            let bytes = Int(source.size.width * source.size.height * 4)
            cache.setObject(source, forKey: key, cost: bytes)
            return source
        }
        let (icon, cost) = downsampled(source)
        cache.setObject(icon, forKey: key, cost: cost)
        return icon
    }

    static func loadImageAsync(atPath path: String) async -> NSImage? {
        if let cached = cachedImage(atPath: path) { return cached }
        return await Task.detached(priority: .userInitiated) {
            Decoded(image: imageIcon(atPath: path))
        }.value.image
    }

    /// An icon read straight from an image file — an extension ships a PNG, which `NSWorkspace` would
    /// otherwise answer with the generic document icon.
    static func imageIcon(atPath path: String) -> NSImage {
        let key = "image:" + path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let source = NSImage(contentsOfFile: path) else {
            return symbolIcon(named: "puzzlepiece.extension")
        }
        let (icon, cost) = downsampled(source)
        cache.setObject(icon, forKey: key, cost: cost)
        return icon
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
    private var matchCache: (query: String, result: [AppEntry])?

    private var isRefreshing = false

    /// Disk-scanned entries, kept apart from `extensionCommands` so either can be refreshed alone.
    private var scanned: [AppEntry] = []
    private var extensionCommands: [AppEntry] = []

    /// Re-scan (called on every launcher open); the in-flight guard drops overlapping reopens and `apps` is only re-published when the set changed, so an unchanged reopen does no UI work.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let found = await Task.detached(priority: .utility) { AppIndex.scan() }.value
        guard found != scanned else { return }
        scanned = found
        rebuild()
    }

    /// Called by `ExtensionManager` whenever the installed set changes.
    func setExtensionCommands(_ entries: [AppEntry]) {
        guard entries != extensionCommands else { return }
        extensionCommands = entries
        rebuild()
    }

    /// Apps, extension commands, Settings panes, then built-in commands — the sectioned launcher
    /// relies on this order so its flat selection index maps 1:1 onto rows.
    private func rebuild() {
        let applications = scanned.filter { $0.kind == .application }
        let rest = scanned.filter { $0.kind != .application }
        apps = applications + extensionCommands + rest
        matchCache = nil
    }

    /// Every `.app` in the standard search directories, in scan order. Also serves extensions'
    /// `getApplications()`.
    nonisolated static func installedApplicationURLs() -> [URL] {
        let fm = FileManager.default
        var searchDirs = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
        ].map { URL(fileURLWithPath: $0) }
        searchDirs.append(fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications"))

        return searchDirs.flatMap { dir -> [URL] in
            let items =
                (try? fm.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            return items.filter { $0.pathExtension == "app" }
        }
    }

    nonisolated private static func scan() -> [AppEntry] {
        var seenBundleIDs = Set<String>()
        var result: [AppEntry] = []
        for url in installedApplicationURLs() {
            let bundle = Bundle(url: url)
            let bundleID = bundle?.bundleIdentifier
            // Dedup by bundle id; first directory (/Applications) wins.
            if let bundleID, !seenBundleIDs.insert(bundleID).inserted { continue }

            let name =
                (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            result.append(
                AppEntry(id: url.path, name: name, url: url, bundleID: bundleID, kind: .application))
        }
        // Apps, then Settings panes, then Commands — the sectioned launcher relies on this order so its flat selection index maps 1:1 onto rows.
        let apps = result.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return apps + SettingsPaneScanner.scan() + CommandRegistry.all
    }

    /// Ranked matches. Empty query returns the full alphabetical list.
    func matches(_ query: String, limit: Int = 200) -> [AppEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return apps }
        if let matchCache, matchCache.query == q { return matchCache.result }
        let result = rank(q, limit: limit)
        matchCache = (q, result)
        return result
    }

    private func rank(_ q: String, limit: Int) -> [AppEntry] {
        let scored = apps.compactMap { app -> (AppEntry, Int)? in
            guard let score = FuzzyMatch.score(query: q, candidate: app.name) else { return nil }
            return (app, score)
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
