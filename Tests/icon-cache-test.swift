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

    static func main() {
        var generation = IconCacheGeneration()
        let captured = generation.value
        var stored: [Int] = []

        _ = generation.publish(1, capturedAt: captured) { stored.append($0) }
        expect(stored == [1], "a current decode populates the cache")

        generation.invalidate()
        let stale = generation.publish(2, capturedAt: captured) { stored.append($0) }
        expect(stale == 2, "a stale decode still reaches its active caller")
        expect(stored == [1], "a stale decode cannot repopulate the cache")

        tintedTiles()
        restyling()
        styleFingerprint()

        print(failures == 0 ? "Icon cache tests passed" : "\(failures) tests failed")
        exit(failures == 0 ? 0 : 1)
    }
}
