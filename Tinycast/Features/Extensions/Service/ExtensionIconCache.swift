import AppKit

/// An extension's own artwork, cached and sized for a palette row.
///
/// Split from `IconCache` because the *size* is a different decision, not a different pipeline. An
/// extension ships a flat, fully saturated tile; a macOS icon is a dark squircle whose ground
/// disappears into the palette, so only its glyph reads. Drawn at equal geometry the extension
/// shouts, and the correction is optical rather than a bug fix. Keeping it here means `IconCache`
/// stays the app-and-symbol layer and knows nothing about extensions.
enum ExtensionIconCache {
    /// Below `IconCache.artworkExtent` on purpose — see this type's note. Change it only against a
    /// rendered strip of real icons; the number means nothing on its own.
    static let extent: CGFloat = 0.76

    /// `NSCache` is thread-safe but not `Sendable`, so assert the guarantee once here.
    private final class Cache: NSCache<NSString, NSImage>, @unchecked Sendable {}

    /// Its own budget, not the launcher's: Detail markdown caches images far larger than a row icon.
    private static let cache: Cache = {
        let cache = Cache()
        cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()

    /// A freshly-decoded, thereafter-immutable `NSImage` is safe to move across the actor boundary.
    private struct Decoded: @unchecked Sendable {
        let image: NSImage?
    }

    // MARK: - Shipped with the extension

    /// Cache-only, so a warm row paints on the same frame.
    static func cached(atPath path: String) -> NSImage? { cache.object(forKey: fileKey(path)) }

    /// Read straight from the file: `NSWorkspace` would answer a PNG with the generic document icon.
    static func icon(atPath path: String) -> NSImage {
        let key = fileKey(path)
        if let cached = cache.object(forKey: key) { return cached }
        guard let source = NSImage(contentsOfFile: path) else {
            return IconCache.symbolIcon(named: "puzzlepiece.extension")
        }
        let (icon, cost) = fitted(source)
        cache.setObject(icon, forKey: key, cost: cost)
        return icon
    }

    static func loadAsync(atPath path: String) async -> NSImage? {
        if let cached = cached(atPath: path) { return cached }
        return await Task.detached(priority: .userInitiated) {
            Decoded(image: icon(atPath: path))
        }.value.image
    }

    /// The file as shipped, never rasterized: fitting flattens a GIF to its first frame, and a tile
    /// that is meant to play needs every one of them.
    static func loadOriginalAsync(atPath path: String) async -> NSImage? {
        let key = originalKey(path)
        if let cached = cache.object(forKey: key) { return cached }
        let decoded = await Task.detached(priority: .userInitiated) {
            Decoded(image: NSImage(contentsOfFile: path))
        }.value
        guard let image = decoded.image else { return nil }
        cache.setObject(image, forKey: key, cost: Int(image.size.width * image.size.height * 4))
        return image
    }

    // MARK: - Fetched by the extension

    /// A list row or Detail markdown can name a remote image; fetch once, then serve from the same
    /// cache. A failure caches nothing, so a transient error retries on the next render. `asIcon` is
    /// off for markdown images, which are drawn far larger than a row and keep their own size.
    static func loadRemoteAsync(_ url: URL, asIcon: Bool = true) async -> NSImage? {
        let key = remoteKey(url, asIcon: asIcon)
        if let cached = cache.object(forKey: key) { return cached }
        guard let (data, _) = try? await session.data(from: url) else { return nil }
        let decoded = await Task.detached(priority: .userInitiated) {
            Decoded(image: NSImage(data: data))
        }.value
        guard let source = decoded.image else { return nil }
        guard asIcon else {
            cache.setObject(source, forKey: key, cost: Int(source.size.width * source.size.height * 4))
            return source
        }
        let (icon, cost) = fitted(source)
        cache.setObject(icon, forKey: key, cost: cost)
        return icon
    }

    /// Cacheless, never `URLSession.shared`: an extension names these URLs, so the in-memory cache
    /// above stays the only copy and nothing it asks for reaches a shared on-disk cache.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    // MARK: - Sizing

    /// Scales `source` so it paints `extent` of the canvas. An unmeasurable source is assumed to be
    /// shaped like an app icon, which is the only guess that leaves it near the right size.
    private static func fitted(_ source: NSImage) -> (NSImage, Int) {
        let painted = IconCache.paintedExtent(source) ?? IconCache.artworkExtent
        let side = IconCache.displayPixel * extent / painted
        let inset = (IconCache.displayPixel - side) / 2
        return IconCache.rasterized(
            source, into: NSRect(x: inset, y: inset, width: side, height: side))
    }

    private static func fileKey(_ path: String) -> NSString { ("file:" + path) as NSString }
    private static func originalKey(_ path: String) -> NSString { ("raw:" + path) as NSString }
    private static func remoteKey(_ url: URL, asIcon: Bool) -> NSString {
        ((asIcon ? "remote:" : "full:") + url.absoluteString) as NSString
    }
}
