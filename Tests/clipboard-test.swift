// Standalone test for the clipboard store, compiling the real source rather than a copy.
import Foundation

@main
@MainActor
struct ClipboardTests {
    static var failures = 0
    static var passes = 0

    static func main() {
        pinOrder()
        unpinRejoinsAsNewest()
        pasteLeavesPinsAlone()
        pinsSurvivePruningAndTheWindow()
        pinsLeadFilteredSearches()
        pinnedSlotResolutionUsesVisiblePins()
        textFormClassification()
        colorParsing()
        colorFormatting()
        colorSpaceConversions()
        colorFormatsRoundTrip()
        typeFilterSplitsTheHistory()
        typeFilterJoinsTheSearchMemo()
        persistence()
        exportSeesPastTheMemoryWindow()
        importedImagesArriveOnce()

        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Cases

    /// Pins stack in pin order, oldest pin first, regardless of how old the entries are.
    static func pinOrder() {
        withStore { store, _ in
            store.addText("oldest", sourceBundleID: nil)
            store.addText("middle", sourceBundleID: nil)
            store.addText("newest", sourceBundleID: nil)

            store.togglePinned(item(store, "oldest"))
            expect(texts(store) == ["oldest", "newest", "middle"], "first pin leads the list")

            store.togglePinned(item(store, "middle"))
            expect(
                texts(store) == ["oldest", "middle", "newest"],
                "second pin joins below the first, and does not sort by recency")

            store.togglePinned(item(store, "newest"))
            expect(
                texts(store) == ["oldest", "middle", "newest"],
                "pins hold pin order, not the recency order they had in the history")
        }
    }

    /// Unpinning drops the row in as today's newest entry rather than back where it came from.
    static func unpinRejoinsAsNewest() {
        withStore { store, _ in
            store.addText("a", sourceBundleID: nil)
            store.addText("b", sourceBundleID: nil)
            store.addText("c", sourceBundleID: nil)
            let before = item(store, "a").createdAt

            store.togglePinned(item(store, "a"))
            store.togglePinned(item(store, "a"))

            expect(texts(store) == ["a", "c", "b"], "unpinned row leads the history")
            expect(!item(store, "a").isPinned, "pin stamp cleared")
            expect(item(store, "a").createdAt > before, "unpin re-recencies the row")
        }
    }

    /// Pasting a pinned entry must not reshuffle the Pinned section.
    static func pasteLeavesPinsAlone() {
        withStore { store, _ in
            store.addText("one", sourceBundleID: nil)
            store.addText("two", sourceBundleID: nil)
            store.togglePinned(item(store, "one"))
            store.togglePinned(item(store, "two"))
            let stamp = item(store, "one").createdAt

            store.promote(item(store, "one"))

            expect(texts(store) == ["one", "two"], "promote leaves a pinned row in place")
            expect(item(store, "one").createdAt == stamp, "promote does not rewrite a pinned row")

            store.addText("three", sourceBundleID: nil)
            store.addText("four", sourceBundleID: nil)
            store.promote(item(store, "three"))
            expect(
                texts(store) == ["one", "two", "three", "four"],
                "an unpinned row still promotes to the head of the history")
        }
    }

    /// Retention sweeps everything around a pin but never the pin itself.
    static func pinsSurvivePruningAndTheWindow() {
        withStore { store, dir in
            // Older than the case's 1-day retention, inside the default the import prunes against.
            let old = Date().addingTimeInterval(-2 * 86_400)
            _ = store.importEntries([
                entry("ancient-pinned", at: old),
                entry("ancient-loose", at: old.addingTimeInterval(1)),
                entry("fresh", at: Date())
            ])
            store.togglePinned(item(store, "ancient-pinned"))

            store.maxAge = 86_400
            store.enforceLimits()
            expect(
                Set(texts(store)) == ["ancient-pinned", "fresh"],
                "pruning skips pinned rows and takes the rest")

            // Reopen: the pin must come back even though it is far outside the retention window.
            let reopened = ClipboardStore(directory: dir)
            reopened.maxAge = 86_400
            reopened.load()
            expect(
                Set(texts(reopened)) == ["ancient-pinned", "fresh"],
                "a pin outlives retention across a relaunch")
        }
    }

    /// A pin must lead a filtered search even when the FTS statement's LIMIT cannot reach it.
    static func pinsLeadFilteredSearches() {
        withStore { store, _ in
            var seed: [ClipboardItem] = []
            let base = Date().addingTimeInterval(-10_000)
            // The pinned hit is the oldest of 260 matches; the FTS statement stops at 200.
            seed.append(entry("needle in the haystack", at: base))
            for i in 1...259 {
                seed.append(entry("haystack filler \(i)", at: base.addingTimeInterval(Double(i))))
            }
            _ = store.importEntries(seed)
            store.togglePinned(item(store, "needle in the haystack"))

            let results = store.search("haystack", filter: .all)
            expect(results.count > 200, "FTS results plus the pinned block")
            expect(
                results.first?.text == "needle in the haystack",
                "the pinned match leads the filtered results")
            expect(
                results.filter(\.isPinned).count == 1, "the pinned row is not duplicated")

            // Below the trigram threshold: the fallback path.
            let short = store.search("ne", filter: .all)
            expect(
                short.first?.text == "needle in the haystack",
                "the pinned match leads the fallback search too")
        }
    }

    /// Slot picks are taken from the visible pinned block after query/filter, not from all pins.
    static func pinnedSlotResolutionUsesVisiblePins() {
        withStore { store, _ in
            store.addText("alpha one", sourceBundleID: nil)
            store.addText("beta two", sourceBundleID: nil)
            store.addText("beta three", sourceBundleID: nil)
            store.addText("plain text", sourceBundleID: nil)

            store.togglePinned(item(store, "alpha one"))
            store.togglePinned(item(store, "beta two"))
            store.togglePinned(item(store, "beta three"))

            expect(
                store.pinnedItem(at: 0, in: "", filter: .all)?.text == "alpha one",
                "slot 1 maps to the first pinned row")
            expect(
                store.pinnedItem(at: 2, in: "", filter: .all)?.text == "beta three",
                "slot 3 maps to the third pinned row")
            expect(
                store.pinnedItem(at: 3, in: "", filter: .all) == nil,
                "missing pinned slot returns nil")

            expect(
                store.pinnedItem(at: 0, in: "beta", filter: .all)?.text == "beta two",
                "query narrows the pinned block before slot mapping")
            expect(
                store.pinnedItem(at: 1, in: "beta", filter: .all)?.text == "beta three",
                "slot mapping follows visible pinned order under query")
            expect(
                store.pinnedItem(at: 2, in: "beta", filter: .all) == nil,
                "query can remove pinned slots from reach")

            expect(
                store.pinnedItem(at: 0, in: "", filter: .link) == nil,
                "filter applies before pinned slot mapping")
        }
    }

    /// The link/address classifier, including the filenames that must not read as links.
    static func textFormClassification() {
        let links = [
            "https://apple.com", "http://apple.com/path?q=1", "apple.com", "apple.com/store",
            "www.Apple.com", "vscode://file/tmp/x", "docs.google.com", "bit.ly/abc"
        ]
        for text in links {
            expect(form(text) == .link, "\(text) is a link")
        }

        let addresses = ["hi@apple.com", "mailto:hi@apple.com", "first.last@mail.example.co.uk"]
        for text in addresses {
            expect(form(text) == .email, "\(text) is an address")
        }

        let plain = [
            // Extensions that collide with a real TLD are the whole reason for the TLD set.
            "report.pdf", "index.html", "App.swift", "data.json", "Safari.app", "image.png",
            "hello world", "visit apple.com today", "3.14", "", "   ", "no-dot-at-all",
            "two@at@signs.com", "@apple.com", "hi@localhost", "line one\nline two"
        ]
        for text in plain {
            expect(form(text) == .plain, "\(String(text.prefix(20))) is plain text")
        }

        // A colour is its own form, and beats the prose branch even when written with spaces.
        for text in ["#FF5733", "#0f0", "rgb(255, 87, 51)", "hsl(11, 100%, 60%)"] {
            expect(form(text) == .color, "\(text) is a colour")
        }

        // Past the scan cap, so a multi-MB copy is never walked looking for a scheme.
        expect(
            form("https://apple.com/" + String(repeating: "a", count: 4096)) == .plain,
            "an over-long token is plain by definition")

        expect(
            ClipboardItem(imagePath: "/tmp/x.png", sourceBundleID: nil).textForm == nil,
            "an image has no text form")
    }

    /// Every notation the parser accepts, and the near-misses it must reject.
    static func colorParsing() {
        let cases: [(String, ColorValue)] = [
            ("#FF5733", ColorValue(red: 1, green: 87 / 255, blue: 51 / 255)),
            // Shorthand doubles each digit rather than padding it with a zero.
            ("#0f0", ColorValue(red: 0, green: 1, blue: 0)),
            ("#0f08", ColorValue(red: 0, green: 1, blue: 0, alpha: 136 / 255)),
            ("rgb(255, 87, 51)", ColorValue(red: 1, green: 87 / 255, blue: 51 / 255)),
            ("rgb(0 255 0 / 0.5)", ColorValue(red: 0, green: 1, blue: 0, alpha: 0.5)),
            ("rgba(255,87,51,0.5)", ColorValue(red: 1, green: 87 / 255, blue: 51 / 255, alpha: 0.5)),
            ("hsl(120, 100%, 50%)", ColorValue(red: 0, green: 1, blue: 0)),
            ("hsl(10.6deg 100% 60%)", ColorValue(red: 1, green: 87 / 255, blue: 51 / 255))
        ]
        for (text, expected) in cases {
            guard let parsed = ColorValue.parse(text) else {
                expect(false, "\(text) parses")
                continue
            }
            expect(near(parsed, expected), "\(text) resolves to its components")
        }

        // The byte-level reject runs before any trimming, so its shapes are pinned here too.
        for text in ["#FF5733 and more", "rgb(255, 87, 51) plus", "(255, 87, 51)", "#", "rgb"] {
            expect(ColorValue.parse(text) == nil, "\(text) is not a colour")
        }

        // A hex-shaped word and a malformed digit count must never read as a colour.
        let rejected = [
            "#GGGGGG", "#12345", "#", "report.pdf", "rgb(1, 2)", "rgb(1, 2, 3", "hsl(1, 2, 3, 4, 5)",
            "cmyk(0, 1, 1, 0)", "255, 87, 51", "#" + String(repeating: "f", count: 96),
            // Non-finite literals parse as Doubles, and every notation ends in an `Int(_:)`.
            "rgb(nan, 0, 0)", "hsl(inf, 100%, 50%)", "rgb(1e400, 0, 0)", "rgba(0, 0, 0, nan)",
            // CSS writes an HSL channel as a percentage; `100` would otherwise clamp to white.
            "hsl(120, 100, 50)", "hsl(120 100 50)", "hsla(120, 100, 50, 1)",
            // An argument list is counted, so a hole in it is malformed rather than dropped.
            "rgb(255,,87,51)", "rgb(255,87,51,)", "rgb(255, 87)", "rgb()", "rgb(1,2,3,4,5)",
            // The spellings never mix, so a comma body may not also carry a slash.
            "rgb(1/2, 3, 4)", "rgb(255, 87, 51 / 0.5)", "rgb(0 255 0 / 0.5 / 1)", "rgb(/0.5)",
            // Each side of the slash is counted: flattening reads an alpha as a blue channel.
            "rgb(0 255 / 0.5)", "hsl(120 100% / 50%)", "rgb(0 / 255 0)", "rgb(0 255 0 0)",
            // `Double` reads Swift literals CSS never writes, and `isHexDigit` reads fullwidth.
            "rgb(0x10, 0, 0)", "rgb(1e2, 0, 0)", "rgb(+255, 0, 0)", "#\u{ff46}\u{ff46}\u{ff46}"
        ]
        for text in rejected {
            expect(ColorValue.parse(text) == nil, "\(String(text.prefix(20))) is not a colour")
        }

        // `rgba()` is an alias of `rgb()` under CSS Color 4, so alpha is optional in both.
        for text in [
            "rgba(255, 87, 51)", "rgb(255, 87, 51, 0.5)", "hsla(120, 100%, 50%)",
            "hsl(120, 100%, 50%, 0.5)", "hsl(120, 100%, 50%, 50%)", "rgb(0 255 0)",
            // CSS treats every whitespace alike, and a copied declaration spans lines.
            "rgb(255,\n87,\n51)", "rgb(0\n255\n0)"
        ] {
            expect(ColorValue.parse(text) != nil, "\(String(text.prefix(20))) is a colour")
        }

        // Rounding leaves a chroma of ~1e-16 at a lightness of 1, whose saturation divisor is 0.
        guard let almostWhite = ColorValue.parse("rgb(100%, 100%, 99.99999999999999%)") else {
            expect(false, "an almost-white colour parses")
            return
        }
        expect(
            ColorFormat.offered(for: almostWhite).allSatisfy { !$0.string(for: almostWhite).isEmpty },
            "every notation of an almost-white colour states a value rather than trapping")
        expect(
            almostWhite.hsl.saturation.isFinite, "a zero-span lightness reports no saturation")

        // Four-digit shorthand doubles its alpha digit like the three-digit form doubles the rest.
        expect(
            ColorValue.parse("#0f0f").map { ColorFormat.hexWithAlpha.string(for: $0) }
                == "#00FF00FF",
            "#0f0f is opaque green")
        expect(
            ColorValue.parse("#000000FF")?.hasAlpha == false,
            "an alpha that rounds back to opaque is opaque, so no alpha row is offered")

        // The two directions of the HSL conversion must agree, or a copied value drifts.
        let round = ColorValue(red: 0.2, green: 0.6, blue: 0.9)
        let hsl = round.hsl
        expect(
            near(
                ColorValue(hue: hsl.hue, saturation: hsl.saturation, lightness: hsl.lightness),
                round),
            "HSL round-trips back to the same sRGB components")
    }

    /// What each notation reads as, and which of them an opaque colour is offered.
    static func colorFormatting() {
        guard let color = ColorValue.parse("#FF5733") else {
            expect(false, "the fixture parses")
            return
        }
        expect(ColorFormat.hex.string(for: color) == "#FF5733", "hex is uppercase")
        expect(
            ColorFormat.rgba.string(for: color) == "rgba(255, 87, 51, 1)", "rgba states channels")
        // One decimal, since whole degrees cost up to 5/255 on the way back.
        expect(
            ColorFormat.hsl.string(for: color) == "hsl(10.6deg, 100%, 60%)",
            "hsl keeps the precision that survives a round trip")
        // An exact channel drops its trailing zeros rather than reading `0.210`.
        expect(
            ColorFormat.oklch.string(for: color) == "oklch(68% 0.21 33.7deg)",
            "oklch states three decimals of chroma")
        expect(
            !ColorFormat.offered(for: color).contains(.hslWithAlpha),
            "an opaque colour is offered no alpha-bearing duplicate")

        guard let translucent = ColorValue.parse("rgba(255, 87, 51, 0.5)") else {
            expect(false, "the translucent fixture parses")
            return
        }
        expect(
            ColorFormat.offered(for: translucent) == ColorFormat.allCases,
            "a colour with alpha is offered every notation")
        expect(
            ColorFormat.hexWithAlpha.string(for: translucent) == "#FF573380",
            "alpha is the fourth hex channel")
        expect(
            ColorFormat.primary(for: translucent) == .hexWithAlpha,
            "the notation ↵ copies keeps a translucent colour whole")
        expect(ColorFormat.primary(for: color) == .hex, "an opaque colour copies as plain hex")
    }

    /// The CSS Color 4 spaces, against values a neutral and a known colour must produce.
    static func colorSpaceConversions() {
        guard let grey = ColorValue.parse("#DDDDDD"), let orange = ColorValue.parse("#FF5733")
        else {
            expect(false, "the fixtures parse")
            return
        }
        // A neutral has no hue, and `atan2` over two rounding errors would still name one.
        expect(ColorFormat.oklch.string(for: grey) == "oklch(89.8% 0 0deg)", "nor an Oklch hue")
        // Oklab's axes run to about ±0.4, so a tenth would state most colours as zero.
        expect(
            ColorFormat.oklch.string(for: orange) == "oklch(68% 0.21 33.7deg)", "and Oklch with it")

        // The CSS4 spellings carry alpha behind a slash, and say nothing when there is none.
        guard let translucent = ColorValue.parse("rgba(0, 255, 0, 0.5)") else {
            expect(false, "the translucent fixture parses")
            return
        }
        expect(
            ColorFormat.oklch.string(for: translucent) == "oklch(86.6% 0.295 142.5deg / 0.5)",
            "a slash carries alpha")
        expect(
            ColorFormat.oklch.string(for: orange) == "oklch(68% 0.21 33.7deg)",
            "and an opaque colour states none")
        expect(
            ColorFormat.offered(for: orange).count == ColorFormat.allCases.count - 2,
            "only the two alpha-named spellings are dropped from an opaque colour")
    }

    /// Every offered notation must re-parse to its own colour: one sweep for loss and lost alpha.
    static func colorFormatsRoundTrip() {
        var checked = 0
        for red in stride(from: 0, through: 255, by: 17) {
            for green in stride(from: 0, through: 255, by: 29) {
                for blue in stride(from: 0, through: 255, by: 43) {
                    for alpha in [255, 128] {
                        let color = ColorValue(
                            red: Double(red) / 255, green: Double(green) / 255,
                            blue: Double(blue) / 255, alpha: Double(alpha) / 255)
                        for format in ColorFormat.offered(for: color) {
                            // `oklch()` is copied out but never read back, so it is not swept.
                            guard format != .oklch else { continue }
                            let text = format.string(for: color)
                            guard let back = ColorValue.parse(text) else {
                                expect(false, "\(text) re-parses")
                                return
                            }
                            // An alpha-free notation is an opaque spelling by design.
                            guard near(back, color, matchingAlpha: back.hasAlpha == color.hasAlpha)
                            else {
                                expect(false, "\(text) states the colour it came from")
                                return
                            }
                            checked += 1
                        }
                    }
                }
            }
        }
        expect(checked > 500, "the sweep actually covered the notations")
    }

    /// 8-bit channels are what every notation states, so agreement to a channel is agreement.
    static func near(_ lhs: ColorValue, _ rhs: ColorValue, matchingAlpha: Bool = true) -> Bool {
        var channels = [(lhs.red, rhs.red), (lhs.green, rhs.green), (lhs.blue, rhs.blue)]
        if matchingAlpha { channels.append((lhs.alpha, rhs.alpha)) }
        return channels.allSatisfy { abs($0 - $1) < 1.0 / 255 }
    }

    /// Each filter returns only its own kind, and a pin still leads the block.
    static func typeFilterSplitsTheHistory() {
        withStore { store, _ in
            store.addText("just some prose", sourceBundleID: nil)
            store.addText("https://apple.com", sourceBundleID: nil)
            store.addText("hi@apple.com", sourceBundleID: nil)
            store.addText("second.link.dev", sourceBundleID: nil)
            store.addText("#FF5733", sourceBundleID: nil)
            store.addText("rgb(0 255 0 / 0.5)", sourceBundleID: nil)

            expect(texts(store).count == 6, "every entry under All Types")
            expect(texts(store, filter: .text) == ["just some prose"], "text excludes links")
            expect(
                texts(store, filter: .color) == ["rgb(0 255 0 / 0.5)", "#FF5733"],
                "a colour is its own type, in whichever notation it was written")
            expect(
                texts(store, filter: .link) == ["second.link.dev", "https://apple.com"],
                "links stay newest-first")
            expect(texts(store, filter: .email) == ["hi@apple.com"], "addresses on their own")
            expect(texts(store, filter: .image).isEmpty, "no images were captured")

            store.togglePinned(item(store, "https://apple.com"))
            expect(
                texts(store, filter: .link) == ["https://apple.com", "second.link.dev"],
                "a pinned link leads its filtered block")
        }
    }

    /// The memo keys on the filter too: same query, new filter, different rows.
    static func typeFilterJoinsTheSearchMemo() {
        withStore { store, _ in
            store.addText("shared token prose", sourceBundleID: nil)
            store.addText("shared-token.com", sourceBundleID: nil)

            expect(store.search("shared", filter: .all).count == 2, "both match the query")
            expect(
                store.search("shared", filter: .link).map(\.text) == ["shared-token.com"],
                "the same query under a link filter is not served from the wider memo")
            expect(
                store.search("shared", filter: .text).map(\.text) == ["shared token prose"],
                "and switching filters again re-runs rather than reusing")
            expect(store.search("shared", filter: .all).count == 2, "back to both")
        }
    }

    /// Pin stamps and their order survive a reopen.
    static func persistence() {
        withStore { store, dir in
            store.addText("first", sourceBundleID: nil)
            store.addText("second", sourceBundleID: nil)
            store.addText("third", sourceBundleID: nil)
            store.togglePinned(item(store, "third"))
            store.togglePinned(item(store, "first"))

            let reopened = ClipboardStore(directory: dir)
            reopened.load()
            expect(
                texts(reopened) == ["third", "first", "second"],
                "pin order is restored from disk, not recomputed from recency")

            reopened.togglePinned(item(reopened, "third"))
            expect(texts(reopened) == ["first", "third", "second"], "unpin after a reload")

            reopened.clearAll()
            expect(reopened.items.isEmpty, "Clear History takes pins too")
        }
    }

    /// A backup reads the whole table, not `items` — which stops at the memory window.
    static func exportSeesPastTheMemoryWindow() {
        withStore { store, _ in
            let total = 1_200
            store.importEntries(
                (0..<total).map {
                    ClipboardItem(
                        id: UUID(), kind: .text, text: "entry \($0)", imagePath: nil,
                        createdAt: Date().addingTimeInterval(TimeInterval($0 - total)),
                        sourceBundleID: nil)
                })
            expect(store.items.count < total, "the resident window holds back some of the history")

            var streamed = 0
            var seen = Set<String>()
            ClipboardStore.forEachStoredItem(inDatabaseAt: store.dbURL) { item in
                streamed += 1
                if let text = item.text { seen.insert(text) }
            }
            expect(streamed == total, "the export streams every row, not just the window")
            expect(seen.count == total, "every row arrives exactly once")
        }
    }

    /// Importing one backup twice must not leave a second copy of every image.
    static func importedImagesArriveOnce() {
        withStore { store, dir in
            let staging = dir.appendingPathComponent("staged", isDirectory: true)
            try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let blob = staging.appendingPathComponent("blob.png")
            let staged = ClipboardItem(imagePath: blob.path, sourceBundleID: nil)

            for pass in 1...2 {
                try? Data("png".utf8).write(to: blob)
                let inserted = ClipboardStore.importStoredItems(
                    inDatabaseAt: store.dbURL, adoptingImagesInto: store.imagesDir, [staged])
                expect(inserted == (pass == 1 ? 1 : 0), "pass \(pass) inserts \(2 - pass) row(s)")
            }
            store.load()
            expect(store.items.count == 1, "the second import adds no row")
            let images =
                (try? FileManager.default.contentsOfDirectory(atPath: store.imagesDir.path)) ?? []
            expect(images == ["blob.png"], "and no second copy of the blob")
        }
    }

    // MARK: - Harness

    /// Runs `body` against a store rooted in a fresh temp directory, torn down afterwards.
    static func withStore(_ body: (ClipboardStore, URL) -> Void) {
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        body(ClipboardStore(directory: dir), dir)
    }

    static func scratchDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "tinycast-clipboard-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func form(_ text: String) -> ClipboardItem.TextForm? {
        ClipboardItem(text: text, sourceBundleID: nil).textForm
    }

    static func entry(_ text: String, at date: Date) -> ClipboardItem {
        ClipboardItem(
            id: UUID(), kind: .text, text: text, imagePath: nil, createdAt: date,
            sourceBundleID: nil)
    }

    static func texts(_ store: ClipboardStore, filter: ClipboardFilter = .all) -> [String] {
        store.search("", filter: filter).compactMap(\.text)
    }

    static func item(_ store: ClipboardStore, _ text: String) -> ClipboardItem {
        guard let match = store.items.first(where: { $0.text == text }) else {
            fail("no entry named \(text)")
            exit(1)
        }
        return match
    }

    static func expect(_ condition: Bool, _ label: String) {
        if condition {
            passes += 1
        } else {
            fail(label)
        }
    }

    static func fail(_ label: String) {
        print("FAIL: \(label)")
        failures += 1
    }
}
