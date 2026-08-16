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

    /// A tinted tile is a different icon from the plain one, and from every other tint — the cache
    /// key has to carry the colour, or a re-skinned extension serves whatever was drawn first.
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

        print(failures == 0 ? "Icon cache tests passed" : "\(failures) tests failed")
        exit(failures == 0 ? 0 : 1)
    }
}
