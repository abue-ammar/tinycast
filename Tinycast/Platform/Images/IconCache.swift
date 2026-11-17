import AppKit
import SwiftUI
import Synchronization
import UniformTypeIdentifiers

struct IconCacheGeneration {
    private(set) var value = 0

    mutating func invalidate() {
        value &+= 1
    }

    func publish<Value>(_ item: Value, capturedAt generation: Int, store: (Value) -> Void) -> Value {
        if value == generation { store(item) }
        return item
    }
}

/// SwiftUI tracks any `@Observable` read in `body`, so carrying this in an id is the subscription.
@MainActor
@Observable
final class IconStyleSignal {
    private(set) var generation = 0

    fileprivate func bump() { generation &+= 1 }
}

/// A view's own icon key plus the generation. Building one in `body` is what subscribes the view.
struct IconRequest<Key: Hashable>: Hashable {
    let key: Key
    let generation: Int

    @MainActor
    init(_ key: Key) {
        self.key = key
        self.generation = IconCache.style.generation
    }
}

enum SystemSymbolName {
    // This pair swaps glyphs in Dark, so there each name draws as the other.
    static func resolve(_ name: String, isDark: Bool) -> String {
        guard isDark else { return name }
        switch name {
        case "face.smiling": return "face.smiling.inverse"
        case "face.smiling.inverse": return "face.smiling"
        default: return name
        }
    }
}

/// A feature sets one rather than branching `AppEntry`; `artwork` carries its extent.
enum EntryIcon: Hashable, Sendable {
    /// The stamp is `FileIconStamp`'s: it moves when the file's icon does, retiring the old bitmap.
    case file(stamp: Int)
    case symbol(String)
    /// Drawn as a vector `IconTile`; the bitmap paths below fall back to the plain symbol tile.
    case tile(symbol: String, tint: IconTint)
    case artwork(path: String, extent: CGFloat)
    /// A declared type's icon, for a bundle whose own file icon is a placeholder.
    case contentType(String)
}

struct IconSize: Hashable, Sendable {
    let points: CGFloat
    let scale: CGFloat

    var pixels: Int { Int((points * scale).rounded(.up)) }
}

/// App icons by path, downsampled and byte-bounded, so rows don't re-hit `NSWorkspace`.
enum IconCache {
    /// `NSCache` is thread-safe but not `Sendable`, so assert the guarantee once here.
    private final class Cache: NSCache<NSString, NSImage>, @unchecked Sendable {}

    /// Carries the size so a lookup can reject a bitmap the interface has since resized past.
    private final class RowImage {
        let size: IconSize
        let image: NSImage

        init(size: IconSize, image: NSImage) {
            self.size = size
            self.image = image
        }
    }

    private final class RowCache: NSCache<NSString, RowImage>, @unchecked Sendable {}

    // One entry per file, not per file and size: resizing must replace rows, never accumulate them.
    private static let rowCache: RowCache = {
        let cache = RowCache()
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()

    private static let displayPixel: CGFloat = 48

    private static let cache: Cache = {
        let cache = Cache()
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    // One 200-row result set fits; unlike launcher icons, these are discarded with the list.
    private static let fittedCache: Cache = {
        let cache = Cache()
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()
    private static let fittedGeneration = Mutex(IconCacheGeneration())

    /// Cache-only lookups (never decode) so a row can paint an already-warm icon on the same frame.
    static func cached(forFile path: String, stamp: Int = 0, size: IconSize? = nil) -> NSImage? {
        let key = fileKey(path, stamp)
        guard let size else { return cache.object(forKey: key) }
        guard let entry = rowCache.object(forKey: key), entry.size == size else { return nil }
        return entry.image
    }
    static func cachedSymbol(named name: String) -> NSImage? {
        cache.object(forKey: symbolKey(name))
    }

    /// Tiles rasterize off-main, where a dynamic `NSColor` resolves wrong, so carry the surface.
    private static let darkSurface = Mutex(true)

    /// Only a real change invalidates: most `effectiveAppearance` notifications do not move it.
    @MainActor static func setDarkSurface(_ isDark: Bool) {
        let changed = darkSurface.withLock { surface -> Bool in
            defer { surface = isDark }
            return surface != isDark
        }
        if changed { invalidateStyled() }
    }

    /// Global rather than injected: a missed injection in a menu or list would be silent staleness.
    @MainActor static let style = IconStyleSignal()

    /// The same count, readable off-main because every cache key carries it.
    private static let styleGeneration = Mutex(0)

    /// For icons resolved synchronously in `body`: the read *is* the subscription, so not a no-op.
    @MainActor static func observeStyle() { _ = style.generation }

    /// A surface or icon-style move stales every bitmap; the generation in each key fixes it.
    @MainActor static func invalidateStyled() {
        styleGeneration.withLock { $0 &+= 1 }
        cache.removeAllObjects()
        rowCache.removeAllObjects()
        purgeFitted()
        style.bump()
    }

    /// macOS restyles `NSWorkspace`'s images in place, so these bytes are the only proof it landed.
    static func styleFingerprint() -> Data? {
        let side = 32
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0),
            let ctx = NSGraphicsContext(bitmapImageRep: rep)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        NSWorkspace.shared.icon(forFile: styleProbePath)
            .draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        guard let bytes = rep.bitmapData else { return nil }
        return Data(bytes: bytes, count: rep.bytesPerRow * rep.pixelsHigh)
    }

    private static let styleProbePath = "/System/Library/CoreServices/Finder.app"

    /// In every key, so an in-flight decode writes somewhere unreachable instead of repopulating.
    private static func key(_ body: String) -> NSString {
        "\(styleGeneration.withLock { $0 }):\(body)" as NSString
    }

    private static func symbolKey(_ name: String) -> NSString {
        let surface = darkSurface.withLock { $0 } ? "dark" : "light"
        return key("symbol:\(surface):\(name)")
    }

    /// A freshly-decoded, thereafter-immutable `NSImage` is safe to move across the actor boundary.
    private struct Decoded: @unchecked Sendable {
        let image: NSImage?
        let cost: Int

        init(image: NSImage?, cost: Int = 0) {
            self.image = image
            self.cost = cost
        }
    }

    /// Returns the decode directly, so a purge mid-decode can't strand a placeholder.
    static func loadAsync(forFile path: String, stamp: Int = 0, size: IconSize? = nil) async -> NSImage? {
        if let cached = cached(forFile: path, stamp: stamp, size: size) { return cached }
        return await Task.detached(priority: .userInitiated) { () -> Decoded in
            guard FileManager.default.fileExists(atPath: path) else { return Decoded(image: nil) }
            return Decoded(image: icon(forFile: path, stamp: stamp, size: size))
        }.value.image
    }
    static func loadSymbolAsync(named name: String) async -> NSImage? {
        if let cached = cachedSymbol(named: name) { return cached }
        return await Task.detached(priority: .userInitiated) {
            Decoded(image: symbolIcon(named: name))
        }.value.image
    }

    static func icon(forFile path: String, stamp: Int = 0, size: IconSize? = nil) -> NSImage {
        if let size { return rowIcon(forFile: path, stamp: stamp, size: size) }
        let key = fileKey(path, stamp)
        if let cached = cache.object(forKey: key) { return cached }
        let (icon, cost) = downsampled(NSWorkspace.shared.icon(forFile: path))
        cache.setObject(icon, forKey: key, cost: cost)
        return icon
    }

    private static func rowIcon(forFile path: String, stamp: Int, size: IconSize) -> NSImage {
        if let warm = cached(forFile: path, stamp: stamp, size: size) { return warm }
        let (image, cost) = autoreleasepool { () -> (NSImage, Int) in
            let (source, sourceCost) = downsampled(NSWorkspace.shared.icon(forFile: path))
            return resized(source, to: size) ?? (source, sourceCost)
        }
        rowCache.setObject(RowImage(size: size, image: image), forKey: fileKey(path, stamp), cost: cost)
        return image
    }

    /// Redraws the 96px result rather than the file's icon: AppKit picks its rep and shadow there.
    private static func resized(_ source: NSImage, to size: IconSize) -> (NSImage, Int)? {
        guard size.pixels < Int(displayPixel * 2) else { return nil }
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: size.pixels, pixelsHigh: size.pixels,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        rep.size = NSSize(width: size.points, height: size.points)
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: rep.size))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return (image, rep.bytesPerRow * rep.pixelsHigh)
    }

    static func symbolIcon(named name: String) -> NSImage {
        let key = symbolKey(name)
        if let cached = cache.object(forKey: key) { return cached }

        let side = displayPixel
        let isDark = darkSurface.withLock { $0 }
        let plainInk: CGFloat = isDark ? 1 : 0
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let inset = side * (1 - appIconBody) / 2
            let tile = NSRect(x: 0, y: 0, width: side, height: side).insetBy(dx: inset, dy: inset)
            NSColor.srgbInk(plainInk, alpha: 0.09).setFill()
            appIconShape(in: tile).fill()

            let ink = NSColor.srgbInk(plainInk, alpha: 0.85)
            // A symbol picks its glyph by the drawing appearance, which off-main isn't the surface's.
            NSAppearance(named: isDark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
                guard let symbol = glyph(named: name, ink: ink, isDark: isDark) else { return }
                let size = symbol.size
                symbol.draw(
                    in: NSRect(
                        x: (side - size.width) / 2, y: (side - size.height) / 2,
                        width: size.width, height: size.height))
            }
            return true
        }
        let (icon, cost) = downsampled(image)
        cache.setObject(icon, forKey: key, cost: cost)
        return icon
    }

    private static func glyph(named name: String, ink: NSColor, isDark: Bool) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 21, weight: .medium)
            .applying(.init(paletteColors: [ink]))
        if let symbol = NSImage(
            systemSymbolName: SystemSymbolName.resolve(name, isDark: isDark),
            accessibilityDescription: nil
        )?
        .withSymbolConfiguration(config) {
            return symbol
        }
        guard let asset = NSImage(named: name) else { return nil }
        // A 24pt box lands the asset's ink at the symbols' ~22pt optical height.
        let assetSize = NSSize(width: 24, height: 24)
        return NSImage(size: assetSize, flipped: false) { rect in
            asset.draw(in: rect)
            ink.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    /// What an app icon paints: the reference for every other artwork.
    static let appIconExtent: CGFloat = 0.83
    /// An app icon's body on its canvas, 824 of 1024, so a tile in a row of apps is their size.
    static let appIconBody: CGFloat = 824.0 / 1024
    /// Measured off the system's app icons, whose continuous corner this matches to the pixel.
    static let appIconCornerRatio: CGFloat = 0.26

    private static func appIconShape(in rect: NSRect) -> NSBezierPath {
        let shape = RoundedRectangle(cornerRadius: rect.width * appIconCornerRatio, style: .continuous)
        return NSBezierPath(cgPath: shape.path(in: rect).cgPath)
    }

    /// The caller chooses the extent; this only measures and rasterizes.
    static func fitted(_ source: NSImage, to extent: CGFloat) -> (NSImage, Int) {
        let painted = paintedExtent(source) ?? appIconExtent
        let side = displayPixel * extent / painted
        let inset = (displayPixel - side) / 2
        return rasterized(source, into: NSRect(x: inset, y: inset, width: side, height: side))
    }

    /// Keyed by path and extent, so two features wanting different sizes never serve each other's.
    static func artwork(atPath path: String, extent: CGFloat) -> NSImage {
        let key = artworkKey(path, extent)
        if let cached = cache.object(forKey: key) { return cached }
        guard let source = NSImage(contentsOfFile: path) else {
            return symbolIcon(named: "questionmark.square.dashed")
        }
        let (icon, cost) = fitted(source, to: extent)
        cache.setObject(icon, forKey: key, cost: cost)
        return icon
    }

    static func cachedArtwork(atPath path: String, extent: CGFloat) -> NSImage? {
        cache.object(forKey: artworkKey(path, extent))
    }

    static func loadArtworkAsync(atPath path: String, extent: CGFloat) async -> NSImage? {
        if let cached = cachedArtwork(atPath: path, extent: extent) { return cached }
        return await Task.detached(priority: .userInitiated) {
            Decoded(image: artwork(atPath: path, extent: extent))
        }.value.image
    }

    static func contentTypeIcon(_ identifier: String) -> NSImage {
        let key = contentTypeKey(identifier)
        if let cached = cache.object(forKey: key) { return cached }
        let (icon, cost) = downsampled(NSWorkspace.shared.icon(for: UTType(identifier) ?? .item))
        cache.setObject(icon, forKey: key, cost: cost)
        return icon
    }

    static func cachedContentTypeIcon(_ identifier: String) -> NSImage? {
        cache.object(forKey: contentTypeKey(identifier))
    }

    static func loadContentTypeIconAsync(_ identifier: String) async -> NSImage? {
        if let cached = cachedContentTypeIcon(identifier) { return cached }
        return await Task.detached(priority: .userInitiated) {
            Decoded(image: contentTypeIcon(identifier))
        }.value.image
    }

    private static func contentTypeKey(_ identifier: String) -> NSString {
        key("type:\(identifier)")
    }

    private static func artworkKey(_ path: String, _ extent: CGFloat) -> NSString {
        key("artwork:\(extent):\(path)")
    }

    // MARK: - Drawing an `EntryIcon`

    /// One switch, so a row never has to know which of these paths its entry wants.
    static func icon(for source: EntryIcon, fileURL: URL) -> NSImage {
        switch source {
        case .file(let stamp): return icon(forFile: fileURL.path, stamp: stamp)
        case .symbol(let name), .tile(let name, _): return symbolIcon(named: name)
        case .artwork(let path, let extent): return artwork(atPath: path, extent: extent)
        case .contentType(let identifier): return contentTypeIcon(identifier)
        }
    }

    static func cached(_ source: EntryIcon, fileURL: URL, size: IconSize? = nil) -> NSImage? {
        switch source {
        case .file(let stamp): return cached(forFile: fileURL.path, stamp: stamp, size: size)
        case .symbol(let name), .tile(let name, _): return cachedSymbol(named: name)
        case .artwork(let path, let extent): return cachedArtwork(atPath: path, extent: extent)
        case .contentType(let identifier): return cachedContentTypeIcon(identifier)
        }
    }

    static func loadAsync(_ source: EntryIcon, fileURL: URL, size: IconSize? = nil) async -> NSImage? {
        switch source {
        case .file(let stamp): return await loadAsync(forFile: fileURL.path, stamp: stamp, size: size)
        case .symbol(let name), .tile(let name, _): return await loadSymbolAsync(named: name)
        case .artwork(let path, let extent):
            return await loadArtworkAsync(atPath: path, extent: extent)
        case .contentType(let identifier): return await loadContentTypeIconAsync(identifier)
        }
    }

    static func cachedFitted(forFile path: String) -> NSImage? {
        fittedCache.object(forKey: fittedKey(path))
    }

    /// Like `loadAsync`, normalized so every file type paints to the same visual size.
    static func loadFittedAsync(forFile path: String) async -> NSImage? {
        if let cached = cachedFitted(forFile: path) { return cached }
        let generation = fittedGeneration.withLock { $0.value }
        let decoded = await Task.detached(
            priority: .userInitiated,
            operation: { () -> Decoded in
                guard FileManager.default.fileExists(atPath: path) else {
                    return Decoded(image: nil)
                }
                return fittedIcon(forFile: path)
            }
        ).value
        guard let image = decoded.image, !Task.isCancelled else { return nil }
        return fittedGeneration.withLock { current in
            current.publish(image, capturedAt: generation) { image in
                fittedCache.setObject(image, forKey: fittedKey(path), cost: decoded.cost)
            }
        }
    }

    static func purgeFitted() {
        fittedGeneration.withLock { generation in
            generation.invalidate()
            fittedCache.removeAllObjects()
        }
    }

    private static func fileKey(_ path: String, _ stamp: Int) -> NSString {
        key("file:\(stamp):\(path)")
    }
    private static func fittedKey(_ path: String) -> NSString { key("fit:" + path) }

    private static func fittedIcon(forFile path: String) -> Decoded {
        let (icon, cost) = fittedToArtwork(NSWorkspace.shared.icon(forFile: path))
        return Decoded(image: icon, cost: cost)
    }

    private static func fittedToArtwork(_ source: NSImage) -> (NSImage, Int) {
        fitted(source, to: appIconExtent)
    }

    /// The artwork's larger dimension, measured at 2×: a 1× grid over-reads the extent.
    private static func paintedExtent(_ source: NSImage) -> CGFloat? {
        let pixels = Int(displayPixel * 2)
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bitmapFormat: [], bytesPerRow: 0, bitsPerPixel: 32),
            let data = rep.bitmapData,
            let ctx = NSGraphicsContext(bitmapImageRep: rep)
        else { return nil }
        rep.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()

        var minX = pixels, maxX = -1, minY = pixels, maxY = -1
        for y in 0..<pixels {
            let row = data.advanced(by: y * rep.bytesPerRow)
            for x in 0..<pixels {
                // Alpha above 0.06 starts at byte 16; fainter shadows do not count as artwork.
                guard row[x * 4 + 3] >= 16 else {
                    continue
                }
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        let side = max(maxX - minX + 1, maxY - minY + 1)
        return CGFloat(side) / CGFloat(pixels)
    }

    private static func downsampled(_ source: NSImage) -> (NSImage, Int) {
        rasterized(
            source, into: NSRect(origin: .zero, size: NSSize(width: displayPixel, height: displayPixel)))
    }

    private static func rasterized(_ source: NSImage, into frame: NSRect) -> (NSImage, Int) {
        // Fixed 2×, `NSScreen.main` being main-thread-only, so a detached decode works.
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
        source.draw(in: frame)
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return (image, rep.bytesPerRow * rep.pixelsHigh)
    }
}
