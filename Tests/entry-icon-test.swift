import AppKit
import Foundation

@main
@MainActor
struct EntryIconTests {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        } else {
            print("PASS  \(message)")
        }
    }

    static let red = SymbolTint(key: "red", color: .systemRed)
    static let blue = SymbolTint(key: "blue", color: .systemBlue)

    // MARK: - Identity

    /// `AppEntry.iconKey` interpolates an `EntryIcon` into a string, and a row's async load is keyed
    /// on it. Two icons that render differently but print the same would serve each other's bitmap.
    static func everyCasePrintsDistinctly() {
        let icons: [EntryIcon] = [
            .file,
            .symbol("star"),
            .symbol("bolt"),
            .tintedSymbol(name: "star", tint: red),
            .tintedSymbol(name: "star", tint: blue),
            .tintedSymbol(name: "bolt", tint: red),
            .artwork(path: "/tmp/a.png", extent: 0.76),
            .artwork(path: "/tmp/a.png", extent: 0.83),
            .artwork(path: "/tmp/b.png", extent: 0.76)
        ]
        let printed = Set(icons.map { "\($0)" })
        expect(printed.count == icons.count, "each icon prints uniquely: \(printed.count)/\(icons.count)")
    }

    /// Hashable is what `.task(id:)` compares, so a re-skin has to read as a different value.
    static func hashingSeparatesTheCases() {
        expect(EntryIcon.symbol("star") == EntryIcon.symbol("star"), "the same symbol is equal")
        expect(EntryIcon.symbol("star") != EntryIcon.symbol("bolt"), "two symbols differ")
        expect(
            EntryIcon.tintedSymbol(name: "star", tint: red)
                != EntryIcon.tintedSymbol(name: "star", tint: blue),
            "two tints of one symbol differ")
        expect(
            EntryIcon.symbol("star") != EntryIcon.tintedSymbol(name: "star", tint: red),
            "a tinted tile differs from the plain one")
        expect(
            EntryIcon.artwork(path: "/tmp/a.png", extent: 0.76)
                != EntryIcon.artwork(path: "/tmp/a.png", extent: 0.83),
            "one file at two extents differs")
        expect(
            Set([EntryIcon.file, .symbol("star"), .file]).count == 2,
            "hashing collapses only equal values")
    }

    // MARK: - Drawing

    /// Each case has to reach its own path. A wrong branch would silently draw the fallback.
    static func everyCaseDraws() {
        let url = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        let cases: [(String, EntryIcon)] = [
            ("file", .file),
            ("symbol", .symbol("star")),
            ("tintedSymbol", .tintedSymbol(name: "star", tint: red))
        ]
        for (label, icon) in cases {
            let image = IconCache.icon(for: icon, fileURL: url)
            expect(image.size.width > 0, "\(label) draws something")
        }
    }

    /// A tint has to reach the tile. Same glyph, two tints, three different bitmaps.
    static func tintsAndSymbolsDoNotShareABitmap() {
        let url = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        let plain = bitmap(IconCache.icon(for: .symbol("star"), fileURL: url))
        let redTile = bitmap(IconCache.icon(for: .tintedSymbol(name: "star", tint: red), fileURL: url))
        let blueTile = bitmap(IconCache.icon(for: .tintedSymbol(name: "star", tint: blue), fileURL: url))

        expect(plain != nil && redTile != nil && blueTile != nil, "all three rasterize")
        expect(plain != redTile, "a tinted tile differs from the plain one")
        expect(redTile != blueTile, "two tints do not share a cache entry")
    }

    /// The whole point of carrying `extent`: one file, two sizes, and neither serves the other.
    static func oneFileAtTwoExtentsDiffers() {
        guard let path = writePNG() else { return expect(false, "the fixture writes") }
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }

        let small = IconCache.icon(for: .artwork(path: path.path, extent: 0.60), fileURL: path)
        let large = IconCache.icon(for: .artwork(path: path.path, extent: 0.90), fileURL: path)

        guard let smallInk = inkExtent(small), let largeInk = inkExtent(large) else {
            return expect(false, "both artwork sizes rasterize")
        }
        expect(smallInk < largeInk, "a smaller extent draws smaller ink: \(smallInk) vs \(largeInk)")
        expect(bitmap(small) != bitmap(large), "two extents do not share a cache entry")
    }

    /// A second ask must hit the cache, not redraw — that is what keeps a scrolled list cheap.
    static func askingTwiceIsStable() {
        let url = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        let first = bitmap(IconCache.icon(for: .tintedSymbol(name: "gear", tint: red), fileURL: url))
        let second = bitmap(IconCache.icon(for: .tintedSymbol(name: "gear", tint: red), fileURL: url))
        expect(first != nil && first == second, "the same icon is stable across two asks")
    }

    /// Cache-only lookups must answer for a warm icon and stay silent for a cold one.
    static func cacheOnlyLookupMatchesTheDrawnIcon() {
        let url = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        let cold = EntryIcon.symbol("nonexistent.glyph.\(UUID().uuidString)")
        expect(IconCache.cached(cold, fileURL: url) == nil, "a cold icon is not reported warm")

        let warm = EntryIcon.symbol("bookmark")
        _ = IconCache.icon(for: warm, fileURL: url)
        expect(IconCache.cached(warm, fileURL: url) != nil, "a drawn icon is reported warm")
    }

    // MARK: - Helpers

    static func bitmap(_ image: NSImage) -> Data? { image.tiffRepresentation }

    /// A red square filling its canvas, so fitting it to an extent is visible in the result.
    static func writePNG() -> URL? {
        let side = 256
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0), let ctx = NSGraphicsContext(bitmapImageRep: rep)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill()
        NSGraphicsContext.restoreGraphicsState()

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("entry-icon-test-\(UUID().uuidString)")
        guard let data = rep.representation(using: .png, properties: [:]),
            (try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true))
                != nil
        else { return nil }
        let url = dir.appendingPathComponent("fixture.png")
        return (try? data.write(to: url)) != nil ? url : nil
    }

    /// The larger side of the alpha bounding box, as a share of the canvas.
    static func inkExtent(_ image: NSImage) -> CGFloat? {
        let side = 96
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0), let ctx = NSGraphicsContext(bitmapImageRep: rep)
        else { return nil }
        rep.size = NSSize(width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()

        var minX = side, maxX = -1, minY = side, maxY = -1
        for y in 0..<side {
            for x in 0..<side where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.06 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGFloat(max(maxX - minX + 1, maxY - minY + 1)) / CGFloat(side)
    }

    static func main() {
        everyCasePrintsDistinctly()
        hashingSeparatesTheCases()
        everyCaseDraws()
        tintsAndSymbolsDoNotShareABitmap()
        oneFileAtTwoExtentsDiffers()
        askingTwiceIsStable()
        cacheOnlyLookupMatchesTheDrawnIcon()

        print(failures == 0 ? "Entry icon tests passed" : "\(failures) tests failed")
        exit(failures == 0 ? 0 : 1)
    }
}
