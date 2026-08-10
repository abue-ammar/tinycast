import AppKit
import Synchronization

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

/// App icons by path, downsampled and byte-bounded, so rows don't re-hit `NSWorkspace`.
enum IconCache {
    /// `NSCache` is thread-safe but not `Sendable`, so assert the guarantee once here.
    private final class Cache: NSCache<NSString, NSImage>, @unchecked Sendable {}

    // Plenty for the ≤24pt draw, and a scrolled `LazyVStack` pins every row's icon.
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
    static func cached(forFile path: String) -> NSImage? { cache.object(forKey: path as NSString) }
    static func cachedSymbol(named name: String) -> NSImage? {
        cache.object(forKey: ("symbol:" + name) as NSString)
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

    /// Command icons: a symbol on a tile, in the same shape as a real app icon.
    static func symbolIcon(named name: String) -> NSImage {
        let key = "symbol:" + name as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let side = displayPixel
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            // Tile inset mirrors the margin macOS app icons carry inside their canvas.
            let tile = NSRect(x: 0, y: 0, width: side, height: side).insetBy(dx: 4, dy: 4)
            NSColor.white.withAlphaComponent(0.09).setFill()
            NSBezierPath(roundedRect: tile, xRadius: 9, yRadius: 9).fill()

            guard let symbol = glyph(named: name, tint: .white.withAlphaComponent(0.85))
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

    /// Symbols where they exist; the names SF Symbols lacks fall back to template assets.
    private static func glyph(named name: String, tint: NSColor) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 21, weight: .medium)
            .applying(.init(paletteColors: [tint]))
        if let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        {
            return symbol
        }
        guard let asset = NSImage(named: name) else { return nil }
        // A 24pt box lands the asset's ink at the symbols' ~22pt optical height.
        let assetSize = NSSize(width: 24, height: 24)
        return NSImage(size: assetSize, flipped: false) { rect in
            asset.draw(in: rect)
            tint.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    /// The share of its canvas an app icon paints; folders and documents differ, so scale.
    private static let artworkExtent: CGFloat = 0.83

    /// Cache-only lookup for `loadFittedAsync`.
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

    private static func fittedKey(_ path: String) -> NSString { ("fit:" + path) as NSString }

    private static func fittedIcon(forFile path: String) -> Decoded {
        let source = NSWorkspace.shared.icon(forFile: path)
        // Solving `side * extent == displayPixel * artworkExtent` leaves an app icon as-is.
        let extent = paintedExtent(source) ?? artworkExtent
        let side = displayPixel * artworkExtent / extent
        let inset = (displayPixel - side) / 2
        let (icon, cost) = rasterized(
            source, into: NSRect(x: inset, y: inset, width: side, height: side))
        return Decoded(image: icon, cost: cost)
    }

    /// The artwork's larger dimension, measured at 2×: a 1× grid over-reads the extent.
    private static func paintedExtent(_ source: NSImage) -> CGFloat? {
        let pixels = Int(displayPixel * 2)
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0),
            let ctx = NSGraphicsContext(bitmapImageRep: rep)
        else { return nil }
        rep.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()

        var minX = pixels, maxX = -1, minY = pixels, maxY = -1
        for y in 0..<pixels {
            for x in 0..<pixels {
                // A faint antialiased edge isn't artwork; 0.06 keeps a drop shadow from counting.
                guard let colour = rep.colorAt(x: x, y: y), colour.alphaComponent > 0.06 else {
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

    /// Rasterize the multi-rep icon into one square bitmap, with its decoded byte cost.
    private static func downsampled(_ source: NSImage) -> (NSImage, Int) {
        rasterized(
            source, into: NSRect(origin: .zero, size: NSSize(width: displayPixel, height: displayPixel)))
    }

    /// Draws `source` into `frame` on a `displayPixel`-square canvas.
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
