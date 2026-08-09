import Foundation

@main
struct RankingTest {
    @MainActor
    static func main() async {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-ranking-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

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

        // Mirrors how AppIndex.rank reads the table: one boosts(query:) pass, then a per-item lookup.
        func boost(_ store: LauncherRankingStore, _ itemKey: String, _ query: String) -> Int {
            store.boosts(query: query)[itemKey] ?? 0
        }

        let whatsApp = "net.whatsapp.WhatsApp"
        let wick = "com.example.wick"
        let cafe = "com.example.cafe"

        check(
            "query key trims surrounding whitespace",
            LauncherRankingStore.normalize(" wha \n") == "wha")
        check("query key folds case", LauncherRankingStore.normalize("WhA") == "wha")
        check("query key folds diacritics", LauncherRankingStore.normalize("Café") == "cafe")
        // A Turkish fold maps "I" to "ı"; asserting the difference keeps this from going vacuous if that ever stops being true.
        check(
            "query key is locale-independent",
            LauncherRankingStore.normalize("I") == "i"
                && LauncherRankingStore.normalize("I")
                    != "I".folding(
                        options: [.caseInsensitive, .diacriticInsensitive],
                        locale: Locale(identifier: "tr_TR"))
        )

        check("unvisited result has no boost", boost(store, whatsApp, "w") == 0)
        check("an unlearned query yields an empty table", store.boosts(query: "w").isEmpty)

        store.record(itemKey: cafe, query: " Café ")
        check(
            "a learned query is recalled through its normalized key",
            boost(store, cafe, "cafe") > 0)

        store.record(itemKey: whatsApp, query: "Wha")
        let firstBoost = boost(store, whatsApp, "w")
        check("visit teaches first query prefix", firstBoost > 0)
        check("visit teaches full normalized query", boost(store, whatsApp, "WHA") > 0)
        check("visit does not teach a different query", boost(store, whatsApp, "wa") == 0)

        // Golden values: these pin the frecency curve, so a change to the scoring has to be deliberate rather than incidental.
        check("one visit, same day, scores 2100", firstBoost == 2_100)
        for _ in 0..<9 { store.record(itemKey: whatsApp, query: "Wha") }
        check("ten visits, same day, score 3576", boost(store, whatsApp, "w") == 3_576)
        clock.addTimeInterval(14 * 86_400)
        check("ten visits, one half-life later, score 2627", boost(store, whatsApp, "w") == 2_627)
        clock.addTimeInterval(351 * 86_400)
        check("ten visits, a year later, score 2076", boost(store, whatsApp, "w") == 2_076)
        for _ in 0..<200 { store.record(itemKey: wick, query: "w") }
        check("the blend is capped at 4500", boost(store, wick, "w") == 4_500)

        store.resetAll()
        store.record(itemKey: whatsApp, query: "Wha")
        let sameDay = boost(store, whatsApp, "w")
        store.record(itemKey: whatsApp, query: "Wha")
        check("frequency increases the boost", boost(store, whatsApp, "w") > sameDay)

        clock.addTimeInterval(60 * 86_400)
        check("recency decays over time", boost(store, whatsApp, "w") < sameDay)

        for _ in 0..<100 { store.record(itemKey: whatsApp, query: "w") }
        clock.addTimeInterval(60 * 86_400)
        let oldFrequentBoost = boost(store, whatsApp, "w")
        for _ in 0..<8 { store.record(itemKey: wick, query: "w") }
        check(
            "a newer habit can overtake an old frequent result",
            boost(store, wick, "w") > oldFrequentBoost)

        let table = store.boosts(query: "w")
        check(
            "one pass returns every item learned for the query",
            Set(table.keys) == [whatsApp, wick])

        let persistedWickBoost = boost(store, wick, "w")
        // Persisting is off-main, so the reload has to meet it before it can read the file.
        await store.flush()
        let reloaded = LauncherRankingStore(fileURL: fileURL) { clock }
        check(
            "records persist across store instances",
            boost(reloaded, wick, "w") == persistedWickBoost)

        reloaded.reset(itemKey: whatsApp)
        check("per-item reset clears every learned query", !reloaded.hasRanking(for: whatsApp))
        check("per-item reset preserves other items", reloaded.hasRanking(for: wick))

        reloaded.resetAll()
        check("global reset clears all learned ranking", reloaded.isEmpty)

        // No amount of learning lets a weaker field outrank a stronger one.
        let alias = SearchFields(names: ["ChatGPT"], alternateNames: ["Codex"])
        let displayName = SearchFields(names: ["Codex Viewer"])
        let identifier = SearchFields(names: ["Unrelated"], bundleID: "com.openai.codex")

        store.resetAll()
        for _ in 0..<500 { store.record(itemKey: alias.names[0], query: "codex") }
        let maxBoost = boost(store, alias.names[0], "codex")
        check("the learned table is saturated for this query", maxBoost == 4_500)

        func relevance(_ fields: SearchFields, _ query: String) -> Int {
            SearchRelevance.score(query: query, fields: fields)!
        }
        check(
            "a saturated boost cannot lift an alias hit over a display-name hit",
            relevance(alias, "codex") + maxBoost < relevance(displayName, "codex"))
        check(
            "a saturated boost cannot lift an identifier hit over an alias hit",
            relevance(identifier, "codex") + maxBoost < relevance(alias, "codex"))
        check(
            "a saturated boost cannot cross a FuzzyMatch tier",
            relevance(SearchFields(names: ["Codex Pro"]), "codex") + maxBoost
                < relevance(SearchFields(names: ["Codex"]), "codex"))
        check(
            "a saturated boost still reorders within one tier",
            relevance(SearchFields(names: ["Codexes"]), "codex") + maxBoost
                > relevance(SearchFields(names: ["Codex Pro"]), "codex"))
        check(
            "the observed boost cap stays under a band stride",
            maxBoost < SearchRelevance.bandStride - FuzzyMatch.maximumScore)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
