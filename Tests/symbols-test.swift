// Standalone test for the SF Symbol catalog — compiles the *real* source (no copy to sync):
// swiftc Tinycast/Core/Extensions/SymbolCatalog.swift Tools/symbols-test.swift -o /tmp/symbols-test && /tmp/symbols-test
//
// It reads this machine's CoreGlyphs bundle, so it asserts shapes and invariants rather than exact
// counts — those move with every macOS release.

import AppKit

@main
@MainActor
struct SymbolTests {
    static var failures = 0
    static var passes = 0

    static func main() {
        let catalog = SymbolCatalog.load()

        check("the system catalog loads", catalog.symbols.count > 1_000, "got \(catalog.symbols.count)")
        check(
            "it's more than the curated set",
            catalog.symbols.count > SymbolCatalog.suggested.count * 10)
        check("no duplicates", Set(catalog.symbols).count == catalog.symbols.count)

        // Everything offered has to actually render, or the picker shows an empty tile. The app's
        // own marks are asset-catalog images rather than system symbols — they are exactly the ones
        // the system cannot draw, which is why they ship — so they're checked separately below.
        let unrenderable = catalog.symbols.prefix(400)
            .filter { !SymbolCatalog.isBundled($0) }
            .filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }
        check("the first 400 all render", unrenderable.isEmpty, "got \(unrenderable.prefix(5))")

        // A bundled mark must not collide with a system symbol name, or the asset would shadow it.
        let colliding = SymbolCatalog.bundledGlyphs.filter {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
        }
        check(
            "bundled marks name nothing the system already has", colliding.isEmpty,
            "got \(colliding)")

        // Apple's reserved marks must not be on offer.
        for reserved in ["icloud", "applelogo", "airplayvideo"] where catalog.symbols.contains(reserved) {
            fail("reserved symbol offered", detail: reserved)
        }
        check("reserved marks are filtered", !catalog.symbols.contains("icloud"))

        // Locale variants are near-duplicates of a symbol that's already listed.
        let locale = catalog.symbols.filter { $0.hasSuffix(".ar") || $0.hasSuffix(".rtl") }
        check("locale variants are filtered", locale.isEmpty, "got \(locale.prefix(5))")

        // Categories: the two synthetic ones plus real subjects, each non-empty.
        check("suggested is first", catalog.categories.first == .suggested)
        // The app's own marks come next: they are the ones the system catalogue does not have.
        check("the bundled marks are second", catalog.categories.dropFirst().first == .bundled)
        check("all symbols is third", catalog.categories.dropFirst(2).first == .all)
        check(
            "every bundled mark is offered",
            SymbolCatalog.bundledGlyphs.allSatisfy(catalog.symbols.contains))
        check(
            "and they lead the suggested set",
            Array(SymbolCatalog.suggested.prefix(SymbolCatalog.bundledGlyphs.count))
                == SymbolCatalog.bundledGlyphs)
        // The system has no bluetooth glyph at all, which is why the app ships one.
        check(
            "bluetooth is reachable",
            catalog.search("bluetooth", in: .all).contains("bluetooth"))
        check("subject categories exist", catalog.categories.count > 10)
        let empty = catalog.categories.filter { catalog.symbols(in: $0).isEmpty }
        check("no empty category", empty.isEmpty, "got \(empty.map(\.title))")
        check(
            "rendering-mode buckets are not categories",
            !catalog.categories.contains { $0.id == "multicolor" || $0.id == "variable" })

        // Search: by name, by the system's own search terms, and across words.
        check(
            "'coffee' finds the cup", catalog.search("coffee", in: .all).contains("cup.and.saucer"),
            "got \(catalog.search("coffee", in: .all).prefix(5))")
        check(
            "name search works", catalog.search("cup.and.saucer", in: .all).contains("cup.and.saucer"))
        check(
            "words can be given in any order",
            catalog.search("saucer cup", in: .all).contains("cup.and.saucer"))
        check("nonsense matches nothing", catalog.search("zzzqqq", in: .all).isEmpty)
        check(
            "an empty query is the whole category",
            catalog.search("", in: .all).count == catalog.symbols.count)
        // Searching from Suggested still looks at everything — a curated set of 88 is not a search index.
        check(
            "search escapes the suggested set",
            catalog.search("thermometer", in: .suggested).count > 1)

        // The fallback stands in when CoreGlyphs isn't where we expect it.
        check("the fallback is usable", !SymbolCatalog.fallback.symbols.isEmpty)
        check(
            "the fallback is the curated set",
            SymbolCatalog.fallback.symbols.allSatisfy(SymbolCatalog.suggested.contains))
        check(
            "every curated symbol renders",
            SymbolCatalog.fallback.symbols.count == SymbolCatalog.suggested.count,
            "\(SymbolCatalog.suggested.count - SymbolCatalog.fallback.symbols.count) missing")

        print(
            failures == 0 ? "\nAll \(passes) checks passed." : "\n\(failures) failure(s), \(passes) passed.")
        exit(failures == 0 ? 0 : 1)
    }

    static func check(_ desc: String, _ condition: Bool, _ detail: String = "") {
        if condition {
            passes += 1
        } else {
            fail(desc, detail: detail)
        }
    }

    static func fail(_ desc: String, detail: String) {
        failures += 1
        print("FAIL  \(desc)  \(detail)")
    }
}
