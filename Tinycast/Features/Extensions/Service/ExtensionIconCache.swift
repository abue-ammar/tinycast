import AppKit

/// An extension's artwork. See docs/features/extensions.md for why it draws smaller than an app icon.
enum ExtensionIconCache {
    /// Below `IconCache.appIconExtent` on purpose; change it only against a rendered strip of icons.
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
    static func cached(atPath path: String) -> NSImage? {
        IconCache.cachedArtwork(atPath: path, extent: extent)
    }

    /// Read from the file: `NSWorkspace` would answer a PNG with the generic document icon.
    static func icon(atPath path: String) -> NSImage {
        guard FileManager.default.fileExists(atPath: path) else {
            return IconCache.symbolIcon(named: "puzzlepiece.extension")
        }
        return IconCache.artwork(atPath: path, extent: extent)
    }

    static func loadAsync(atPath path: String) async -> NSImage? {
        guard FileManager.default.fileExists(atPath: path) else {
            return IconCache.symbolIcon(named: "puzzlepiece.extension")
        }
        return await IconCache.loadArtworkAsync(atPath: path, extent: extent)
    }

    /// Never rasterized: fitting flattens a GIF to its first frame, and a playing tile needs them all.
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

    // MARK: - Carried inline by the extension

    /// The bytes a `data:` URL holds, with `palette` resolved into them so no render pass pays for
    /// it. Uncached and unfitted: the payload is resident, and the extension has already sized it.
    static func loadInlineAsync(_ url: URL, palette: [String: String]) async -> NSImage? {
        guard let data = inlineData(url) else { return nil }
        let names = isSVG(url) ? palette : [:]
        return await Task.detached(priority: .userInitiated) {
            Decoded(image: NSImage(data: resolvingPaletteNames(in: data, palette: names)))
        }.value.image
    }

    /// A `raycast-*` colour name is legal wherever a tint is, so an extension drawing its own SVG
    /// writes one straight into `stroke` — no renderer knows the keyword and the shape draws nothing.
    private static func resolvingPaletteNames(in data: Data, palette: [String: String]) -> Data {
        guard !palette.isEmpty, let source = String(data: data, encoding: .utf8),
            let rewritten = rewritingNames(in: source, palette: palette)
        else { return data }
        return Data(rewritten.utf8)
    }

    /// Walked as whole names rather than searched for known ones: `raycast-red` sits inside
    /// `raycast-red-invented`, and substituting it there would corrupt a name this cannot resolve.
    private static func rewritingNames(in text: String, palette: [String: String]) -> String? {
        // `.literal`: the default search is Unicode-canonical and costs 3x on a long payload.
        guard text.range(of: paletteNamePrefix, options: .literal) != nil else { return nil }
        var resolved = ""
        var rest = Substring(text)
        while let match = rest.range(of: paletteNamePrefix, options: .literal) {
            let name = rest[match.lowerBound...].prefix { paletteNameCharacters.contains($0) }
            resolved += rest[..<match.lowerBound]
            resolved += palette[String(name)] ?? String(name)
            rest = rest[name.endIndex...]
        }
        return resolved + rest
    }

    private static let paletteNamePrefix = "raycast-"
    private static let paletteNameCharacters = Set("abcdefghijklmnopqrstuvwxyz-")

    /// Only a payload that says it is an SVG is decoded as text; a photo is left byte-identical.
    /// Case-insensitive because a media type is, and `image/SVG+XML` is a legal spelling.
    private static func isSVG(_ url: URL) -> Bool {
        let text = url.absoluteString
        guard let comma = text.firstIndex(of: ",") else { return false }
        return text[..<comma].range(of: "svg", options: .caseInsensitive) != nil
    }

    /// `data:[<mediatype>][;base64],<payload>`, minus any query — Detail markdown appends Raycast's
    /// `?raycast-width=…` sizing hints, and neither encoding can produce a `?` of its own.
    private static func inlineData(_ url: URL) -> Data? {
        let text = url.absoluteString
        guard let comma = text.firstIndex(of: ",") else { return nil }
        let payload = String(text[text.index(after: comma)...].prefix { $0 != "?" })
        guard text[..<comma].hasSuffix(";base64") else {
            return payload.removingPercentEncoding.map { Data($0.utf8) }
        }
        return Data(base64Encoded: payload, options: .ignoreUnknownCharacters)
    }

    // MARK: - Fetched by the extension

    /// A failure caches nothing, so a transient error retries; `asIcon` is off for markdown images.
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
        let (icon, cost) = IconCache.fitted(source, to: extent)
        cache.setObject(icon, forKey: key, cost: cost)
        return icon
    }

    /// Cacheless, never `URLSession.shared`: an extension names these URLs, so none reach a disk cache.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private static func originalKey(_ path: String) -> NSString { ("raw:" + path) as NSString }
    private static func remoteKey(_ url: URL, asIcon: Bool) -> NSString {
        ((asIcon ? "remote:" : "full:") + url.absoluteString) as NSString
    }
}
