import AppKit
import Foundation

@main
@MainActor
struct IconCacheTests {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    /// The cache key carries the colour, or a re-skin serves whatever was drawn first.
    static func tintedTiles() {
        let plain = bitmap(IconCache.symbolIcon(named: "star"))
        let red = bitmap(
            IconCache.symbolIcon(named: "star", tint: SymbolTint(key: "red", color: .systemRed)))
        let blue = bitmap(
            IconCache.symbolIcon(named: "star", tint: SymbolTint(key: "blue", color: .systemBlue)))

        expect(plain != nil && red != nil && blue != nil, "every tile rasterizes")
        expect(plain != red, "a tinted tile differs from the plain one")
        expect(red != blue, "two tints do not share a cache entry")
        // Same key twice must hit the cache and give back the identical bitmap.
        expect(
            red
                == bitmap(
                    IconCache.symbolIcon(
                        named: "star", tint: SymbolTint(key: "red", color: .systemRed))),
            "the same tint is stable")
    }

    static func bitmap(_ image: NSImage) -> Data? { image.tiffRepresentation }

    /// A restyle has to both drop what is cached and move the generation views key their fetch on.
    static func restyling() {
        let before = IconCache.style.generation
        let warm = IconCache.symbolIcon(named: "star")
        expect(IconCache.cachedSymbol(named: "star") === warm, "a drawn tile is cached")

        IconCache.invalidateStyled()
        expect(IconCache.style.generation == before + 1, "a restyle moves the generation")
        expect(IconCache.cachedSymbol(named: "star") == nil, "a restyle drops what was cached")
        expect(IconRequest("star").generation == IconCache.style.generation, "a request carries it")
        expect(IconRequest("star") != IconRequest("moon"), "the view's own key still separates them")

        // `.initial` and every repeat notification must not invalidate; only a real move may.
        let settled = IconCache.style.generation
        IconCache.setDarkSurface(true)
        expect(IconCache.style.generation == settled, "re-asserting the same surface is free")
        IconCache.setDarkSurface(false)
        expect(IconCache.style.generation == settled + 1, "a changed surface invalidates once")
    }

    /// A probe that rendered nothing would strand every restyle until the settle deadline expired.
    static func styleFingerprint() {
        let first = IconCache.styleFingerprint()
        expect(first != nil, "the style probe renders")
        expect(first == IconCache.styleFingerprint(), "an unchanged style renders identically")
    }

    static let finder = "/System/Library/CoreServices/Finder.app"

    static func pixelWidth(_ image: NSImage) -> Int {
        autoreleasepool { (image.representations.first as? NSBitmapImageRep)?.pixelsWide ?? 0 }
    }

    static func rowSizes() {
        IconCache.invalidateStyled()
        let full = IconCache.icon(forFile: finder)
        expect(pixelWidth(full) == 96, "unsized consumers retain 96px")
        for scale: CGFloat in [1, 2] {
            for points: CGFloat in [24, 26, 29, 24] {
                let size = IconSize(points: points, scale: scale)
                let row = IconCache.icon(forFile: finder, size: size)
                expect(pixelWidth(row) == Int(points * scale), "row follows points and backing scale")
                expect(IconCache.cached(forFile: finder, size: size) === row, "warm row reuses its image")
                expect(
                    IconCache.cached(forFile: finder) === full, "row resizing preserves full-size consumers")
                let other = IconSize(points: points + 1, scale: scale)
                expect(IconCache.cached(forFile: finder, size: other) == nil, "wrong sizes never hit")
            }
        }
        let fractional = IconSize(points: 26.4, scale: 2)
        expect(pixelWidth(IconCache.icon(forFile: finder, size: fractional)) == 53, "round pixels up")
        let size = IconSize(points: 24, scale: 2)
        let first = IconCache.icon(forFile: finder, stamp: 1, size: size)
        let changed = IconCache.icon(forFile: finder, stamp: 2, size: size)
        expect(first !== changed, "file stamps separate row entries")
        IconCache.invalidateStyled()
        expect(IconCache.cached(forFile: finder, stamp: 2, size: size) == nil, "restyle clears rows")
        let newer = IconCache.icon(forFile: finder, stamp: 2, size: size)
        expect(newer !== changed, "a style change regenerates a row")
    }

    static func rowLifetime() {
        IconCache.invalidateStyled()
        weak var old: NSImage?
        weak var oldBitmap: NSBitmapImageRep?
        autoreleasepool {
            let image = IconCache.icon(forFile: finder, size: IconSize(points: 24, scale: 2))
            old = image
            oldBitmap = image.representations.first as? NSBitmapImageRep
        }
        expect(old != nil && oldBitmap != nil, "cache holds the current row")
        autoreleasepool {
            _ = IconCache.icon(forFile: finder, size: IconSize(points: 29, scale: 2))
        }
        expect(old == nil && oldBitmap == nil, "replacing a size releases the previous bitmap")
        expect(
            IconCache.cached(forFile: finder, size: IconSize(points: 24, scale: 2)) == nil,
            "previous sizes do not accumulate")
        IconCache.invalidateStyled()
    }

    static func rendered(_ source: NSImage, size: IconSize) -> Data {
        autoreleasepool {
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: size.pixels, pixelsHigh: size.pixels, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = NSSize(width: size.points, height: size.points)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSGraphicsContext.current?.imageInterpolation = .high
            source.draw(in: NSRect(origin: .zero, size: rep.size))
            NSGraphicsContext.restoreGraphicsState()
            return Data(bytes: rep.bitmapData!, count: rep.bytesPerRow * rep.pixelsHigh)
        }
    }

    static func rowRendering() {
        let paths = [
            finder, "/System/Applications/Calculator.app", "/System/Applications/Calendar.app",
            "/System/Applications/Notes.app", "/System/Applications/System Settings.app",
            "/System/Applications/Preview.app"
        ]
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                IconCache.invalidateStyled()
                for path in paths {
                    for scale: CGFloat in [1, 2] {
                        for points: CGFloat in [24, 26, 29] {
                            autoreleasepool {
                                let size = IconSize(points: points, scale: scale)
                                let baseline = IconCache.icon(forFile: path)
                                let candidate = IconCache.icon(forFile: path, size: size)
                                expect(
                                    rendered(baseline, size: size) == rendered(candidate, size: size),
                                    "final-size bytes match: \(path), \(name), \(points)pt @\(scale)x")
                            }
                        }
                    }
                }
            }
        }
    }

    static func asynchronousRows() async {
        let size = IconSize(points: 26, scale: 2)
        IconCache.invalidateStyled()
        let image = await IconCache.loadAsync(.file(stamp: 3), fileURL: URL(filePath: finder), size: size)
        expect(image != nil && pixelWidth(image!) == 52, "entry load carries the requested size off-main")
        expect(
            IconCache.cached(.file(stamp: 3), fileURL: URL(filePath: finder), size: size) === image,
            "entry cache lookup uses the same size")
        let missing = await IconCache.loadAsync(forFile: "/missing-perf-020-file", size: size)
        expect(missing == nil, "a missing path stays a placeholder")
        let symbol = await IconCache.loadAsync(.symbol("star"), fileURL: URL(filePath: finder), size: size)
        expect(symbol === IconCache.symbolIcon(named: "star"), "symbols use the existing rendering path")
    }

    static func main() async {
        var generation = IconCacheGeneration()
        let captured = generation.value
        var stored: [Int] = []

        _ = generation.publish(1, capturedAt: captured) { stored.append($0) }
        expect(stored == [1], "a current decode populates the cache")

        generation.invalidate()
        let stale = generation.publish(2, capturedAt: captured) { stored.append($0) }
        expect(stale == 2, "a stale decode still reaches its active caller")
        expect(stored == [1], "a stale decode cannot repopulate the cache")

        rowSizes()
        rowLifetime()
        rowRendering()
        await asynchronousRows()
        tintedTiles()
        restyling()
        styleFingerprint()

        print(failures == 0 ? "Icon cache tests passed" : "\(failures) tests failed")
        exit(failures == 0 ? 0 : 1)
    }
}
