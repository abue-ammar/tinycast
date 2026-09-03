import Foundation

@main
struct RankingTest {
    @MainActor
    static func main() async {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-ranking-\(UUID().uuidString).json")

        var clock = Date(timeIntervalSince1970: 2_000_000_000)
        let store = LauncherRankingStore(fileURL: fileURL) { clock }
        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        // Mirrors AppIndex.rank: one boosts(query:) pass, then a per-item lookup.
        func boost(_ store: LauncherRankingStore, _ itemKey: String, _ query: String) -> Int {
            store.usage(query: query)[itemKey] ?? 0
        }

        let whatsApp = "net.whatsapp.WhatsApp"
        let wick = "com.example.wick"
        let cafe = "com.example.cafe"

        check(
            "query key trims surrounding whitespace",
            LauncherRankingStore.normalize(" wha \n") == "wha")
        check("query key folds case", LauncherRankingStore.normalize("WhA") == "wha")
        check("query key folds diacritics", LauncherRankingStore.normalize("Café") == "cafe")
        // Matching folds width, so learning must too, or an IME's picks land in an unread bucket.
        check(
            "query key folds full-width input the way matching does",
            LauncherRankingStore.normalize("ｃａｆｅ") == "cafe")
        // A Turkish fold maps "I" to "ı"; asserting the difference keeps this honest.
        check(
            "query key is locale-independent",
            LauncherRankingStore.normalize("I") == "i"
                && LauncherRankingStore.normalize("I")
                    != "I".folding(
                        options: [.caseInsensitive, .diacriticInsensitive],
                        locale: Locale(identifier: "tr_TR"))
        )

        check("unvisited result has no boost", boost(store, whatsApp, "w") == 0)
        check("an unlearned query yields an empty table", store.usage(query: "w").isEmpty)

        store.record(itemKey: cafe, query: " Café ")
        check(
            "a learned query is recalled through its normalized key",
            boost(store, cafe, "cafe") > 0)

        store.record(itemKey: whatsApp, query: "Wha")
        let firstBoost = boost(store, whatsApp, "w")
        check("visit teaches first query prefix", firstBoost > 0)
        check("visit teaches full normalized query", boost(store, whatsApp, "WHA") > 0)
        check("visit does not teach a different query", boost(store, whatsApp, "wa") == 0)

        // Golden values: these pin the frecency curve, so a change has to be deliberate.
        check("one visit, same day, scores 1175", firstBoost == 1_175)
        for _ in 0..<9 { store.record(itemKey: whatsApp, query: "Wha") }
        check("ten visits, same day, score 2026", boost(store, whatsApp, "w") == 2_026)
        clock.addTimeInterval(14 * 86_400)
        check("ten visits, one half-life later, score 1583", boost(store, whatsApp, "w") == 1_583)
        clock.addTimeInterval(351 * 86_400)
        check("ten visits, a year later, score 1326", boost(store, whatsApp, "w") == 1_326)

        // The ceiling the firewall depends on, and the saturation the old curve had at 31 uses.
        check(
            "usage stays under its ceiling however deep a habit runs",
            (1...200_000).allSatisfy {
                LauncherRankingStore.usage(count: $0, lastUsed: clock, share: 1, at: clock)
                    <= LauncherRankingStore.maximumUsage
            })
        check(
            "using something more always counts for more",
            LauncherRankingStore.usage(count: 49, lastUsed: clock, share: 1, at: clock)
                > LauncherRankingStore.usage(count: 31, lastUsed: clock, share: 1, at: clock))

        store.resetAll()
        store.record(itemKey: whatsApp, query: "Wha")
        let sameDay = boost(store, whatsApp, "w")
        store.record(itemKey: whatsApp, query: "Wha")
        check("frequency increases the usage", boost(store, whatsApp, "w") > sameDay)

        clock.addTimeInterval(60 * 86_400)
        check("recency decays over time", boost(store, whatsApp, "w") < sameDay)

        // Frequency leads, so a far larger habit holds even when stale — but at equal counts,
        // the fresher one wins. That split is what keeps a real habit from being outvoted by noise.
        for _ in 0..<100 { store.record(itemKey: whatsApp, query: "w") }
        clock.addTimeInterval(60 * 86_400)
        let staleFrequent = boost(store, whatsApp, "w")
        for _ in 0..<8 { store.record(itemKey: wick, query: "w") }
        check("a much larger habit survives going stale", staleFrequent > boost(store, wick, "w"))
        store.resetAll()
        for _ in 0..<8 { store.record(itemKey: whatsApp, query: "w") }
        clock.addTimeInterval(60 * 86_400)
        let stale = boost(store, whatsApp, "w")
        for _ in 0..<8 { store.record(itemKey: wick, query: "w") }
        check("at equal counts the fresher habit wins", boost(store, wick, "w") > stale)

        let table = store.usage(query: "w")
        check(
            "one pass returns every item learned for the query",
            Set(table.keys) == [whatsApp, wick])

        // The opening list stays alphabetical, so nothing is learned or recalled under "".
        store.resetAll()
        store.record(itemKey: wick, query: "")
        check("a launch with no query teaches nothing", store.isEmpty)
        store.record(itemKey: whatsApp, query: "whatsapp")
        check(
            "one row per query, recalled under every prefix a user might type",
            boost(store, whatsApp, "wh") > 0 && boost(store, whatsApp, "whatsapp") > 0
                && boost(store, whatsApp, "x") == 0)

        store.record(itemKey: wick, query: "wick")
        let persistedWickUsage = boost(store, wick, "wick")
        // Persisting is off-main, so the reload has to meet it before it can read the file.
        await store.flush()
        let reloaded = LauncherRankingStore(fileURL: fileURL) { clock }
        check(
            "records persist across store instances",
            boost(reloaded, wick, "wick") == persistedWickUsage)

        reloaded.reset(itemKey: whatsApp)
        check("per-item reset clears every learned query", !reloaded.hasRanking(for: whatsApp))
        check("per-item reset preserves other items", reloaded.hasRanking(for: wick))

        reloaded.resetAll()
        check("global reset clears all learned ranking", reloaded.isEmpty)

        // What learning may and may not do, now that it is denominated in picks.
        store.resetAll()
        for _ in 0..<500 { store.record(itemKey: "ChatGPT", query: "codex") }
        let saturated = boost(store, "ChatGPT", "codex")
        check(
            "the learned table saturates near its ceiling",
            saturated > 2_500 && saturated <= LauncherRankingStore.maximumUsage)

        func relevance(_ fields: SearchFields, _ query: String) -> Int {
            SearchRelevance.quality(query: query, fields: fields)!
        }
        check(
            "P1 no habit lifts anything over an exactly-typed display name",
            relevance([.name("Unrelated"), .technical("openai.codex")], "codex") + saturated
                < relevance([.name("Codex")], "codex"))
        check(
            "a habit does lift a weaker match over a stronger one — that is the point",
            relevance([.name("ChatGPT"), .translation("Codex")], "codex") + saturated
                > relevance([.name("Codex Viewer")], "codex"))
        check(
            "the observed ceiling keeps the firewall standing",
            SearchRelevance.protectionFloor
                > SearchRelevance.poolTop + SearchRelevance.shapeSpan + saturated)

        try? FileManager.default.removeItem(at: fileURL)
        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
