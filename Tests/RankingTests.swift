import Foundation

@main
struct RankingTests {
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

        func usage(_ key: String) -> LauncherUsage { store.snapshot().usage(for: key) }
        func near(_ value: Double, _ expected: Double) -> Bool { abs(value - expected) < 0.001 }
        let day: TimeInterval = 86_400

        // MARK: - The query fold

        check("a term trims surrounding whitespace", LauncherRankingStore.normalize(" wha \n") == "wha")
        check("a term folds case", LauncherRankingStore.normalize("WhA") == "wha")
        check("a term folds diacritics", LauncherRankingStore.normalize("Café") == "cafe")
        // Matching folds width, so learning must too, or an IME's picks land in an unread bucket.
        check("a term folds full-width input", LauncherRankingStore.normalize("ｃａｆｅ") == "cafe")
        check("a term is stored as the ranking reads it", LauncherRankingStore.normalize("微信") == "wei xin")
        check(
            "a term folds without a locale",
            LauncherRankingStore.normalize("I") == "i"
                && LauncherRankingStore.normalize("I")
                    != "I".folding(options: [.caseInsensitive], locale: Locale(identifier: "tr_TR"))
        )

        // MARK: - Frecency

        let safari = "com.apple.Safari"
        check("an unvisited entry reads as never used", usage(safari) == .unused)
        check("an empty store says so", store.isEmpty)
        store.visit(itemKey: safari, query: "saf")
        check("one visit scores 101", near(usage(safari).frecency, 101))
        check("…and is remembered", store.hasRanking(for: safari) && !store.isEmpty)
        clock += 10 * day
        check("ten days halve it", near(usage(safari).frecency, 50.5))
        store.visit(itemKey: safari, query: nil)
        check("a visit adds 100 to what is left", near(usage(safari).frecency, 150.5))
        clock += 200 * day
        check("a long silence floors it at 1", usage(safari).frecency == 1)

        let order = [0.0, 3, 30].map { offset -> Bool in
            let early = LauncherVisit(anchor: clock + 5 * day, openedAt: clock, searchTerms: [])
            let late = LauncherVisit(anchor: clock + 6 * day, openedAt: clock, searchTerms: [])
            let at = clock + offset * day
            let a = LauncherRankingStore.usage(of: early, at: at).frecency
            let b = LauncherRankingStore.usage(of: late, at: at).frecency
            return offset < 5 ? b > a : a == b
        }
        check("a later anchor stays ahead until both floor", order.allSatisfy { $0 })

        // MARK: - Search terms

        let slack = "com.tinyspeck.slackmacgap"
        store.visit(itemKey: slack, query: " Sa ")
        check("a visit keeps its folded term", usage(slack).searchTerms == ["sa"])
        for term in ["sl", "slack", "sa", "s"] { store.visit(itemKey: slack, query: term) }
        check("only the newest three distinct terms stay", usage(slack).searchTerms == ["slack", "sa", "s"])
        store.visit(itemKey: slack, query: "")
        store.visit(itemKey: slack, query: String(repeating: "x", count: 65))
        check(
            "an empty or pasted query leaves the terms alone",
            usage(slack).searchTerms == ["slack", "sa", "s"])
        clock += 18 * day
        check("terms stop counting after seventeen days", usage(slack).searchTerms.isEmpty)
        check("…while the score still does", usage(slack).frecency > 1)
        store.visit(itemKey: slack, query: "sl")
        check("a fresh open brings the terms back", usage(slack).searchTerms == ["sa", "s", "sl"])

        // MARK: - Persistence

        await store.flush()
        let reloaded = LauncherRankingStore(fileURL: fileURL) { clock }
        check("a visit survives a relaunch", reloaded.visits[slack] == store.visits[slack])
        check("an entry whose score has floored is pruned on load", !reloaded.hasRanking(for: safari))
        check("…the live one stays", reloaded.hasRanking(for: slack))

        let revision = store.revision
        store.reset(itemKey: slack)
        check("a reset forgets one entry", !store.hasRanking(for: slack))
        check("…and moves the revision", store.revision != revision)
        let unchanged = store.revision
        store.reset(itemKey: "missing")
        check("resetting nothing leaves the revision", store.revision == unchanged)
        store.visit(itemKey: "a", query: nil)
        store.visit(itemKey: "b", query: nil)
        store.resetAll()
        check("reset all empties the table", store.isEmpty)

        store.replace([
            "kept": LauncherVisit(anchor: clock + day, openedAt: clock, searchTerms: ["k"]),
            "stale": LauncherVisit(anchor: clock - day, openedAt: clock - 90 * day, searchTerms: []),
            "": LauncherVisit(anchor: clock + day, openedAt: clock, searchTerms: [])
        ])
        check("an import keeps only live, keyed entries", Array(store.visits.keys) == ["kept"])

        await store.flush()
        try? FileManager.default.removeItem(at: fileURL)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
