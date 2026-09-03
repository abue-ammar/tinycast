import Foundation

/// The launcher's ranking over real recorded launches. **A new complaint is a new case here.**
@main
struct CorpusTest {
    struct Entry: Codable {
        let key: String
        let kind: String
        let name: String
        let strongNames: [String]
        let translations: [String]
        var ownerName: String?
        var bundleID: String?
        var executableName: String?

        var fields: SearchFields {
            var sources = EntryNaming.Sources(name: name)
            sources.strongNames = strongNames
            sources.translations = translations
            sources.ownerName = ownerName
            sources.bundleID = bundleID
            sources.executableName = executableName
            return SearchFields(EntryNaming.aliases(for: sources))
        }
    }

    struct Case: Codable {
        let query: String
        let expect: String
        let picks: Int
        /// A rival is named exactly what was typed, so the firewall keeps this one unreachable.
        var protected: Bool?
        /// The query does not match the chosen entry at all — a real mis-pick, kept as recorded.
        var unmatched: Bool?
        var note: String?
    }

    struct Corpus: Codable {
        let entries: [Entry]
        let cases: [Case]
    }

    // MARK: - Thresholds

    /// The chosen entry must match its query. A miss here is a naming bug, not a ranking one.
    static let requiredMatched = 37
    /// Cold means zero learned history — how good the ranking is for a brand-new user.
    static let requiredTop1Cold = 21
    static let requiredTop5Cold = 34
    /// Every unprotected case must be winnable by using it — the assertion the band ladder failed.
    static let requiredReachable = 35
    /// Cases the firewall deliberately keeps unreachable; each names its escape in the fixture.
    static let allowedProtected = 2
    /// Picks a user would plausibly spend before giving up on the launcher entirely.
    static let reachablePicks = 20

    nonisolated(unsafe) static var failures = 0

    static func check(_ description: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
        if condition {
            print("PASS  \(description)")
        } else {
            print("FAIL  \(description)  \(detail())")
            failures += 1
        }
    }

    static func main() {
        let url = URL(fileURLWithPath: "Tests/launcher-corpus/corpus.json")
        guard let data = try? Data(contentsOf: url),
            let corpus = try? JSONDecoder().decode(Corpus.self, from: data)
        else {
            print("FAIL  corpus.json is unreadable — run from the repo root")
            exit(1)
        }
        print("# corpus: \(corpus.entries.count) entries, \(corpus.cases.count) real launches")

        coldAccuracy(corpus)
        reachability(corpus)
        usageCurve()
        emptyQuery(corpus)
        firewall(corpus)
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - Ranking helpers

    /// Mirrors `AppIndex.rank`, but through the shipped fold rather than a copy of it.
    static func rank(
        _ query: String, _ entries: [Entry], usage: [String: Int] = [:], limit: Int = 200
    ) -> [Entry] {
        LauncherOrder.ranked(
            entries, query: FuzzyMatch.Query(query), limit: limit, fields: \.fields,
            usage: { usage[$0.key] ?? 0 }, name: \.name)
    }

    /// The usage an entry earns from `picks` launches of one query, all of them today.
    static func learned(_ picks: Int, share: Double = 1) -> Int {
        LauncherRankingStore.usage(
            count: picks, lastUsed: Date(), share: share, at: Date())
    }

    // MARK: - Cold accuracy

    static func coldAccuracy(_ corpus: Corpus) {
        print("\n# cold ranking — no learned history")
        var matched = 0
        var top1 = 0
        var top5 = 0
        var misses: [String] = []
        for test in corpus.cases where test.unmatched != true {
            // Unlimited: whether the entry matches at all is a naming question, not a top-N one.
            let ranked = rank(test.query, corpus.entries, limit: corpus.entries.count)
            let position = ranked.firstIndex { $0.key == test.expect }
            if position != nil { matched += 1 }
            if position == 0 { top1 += 1 } else { misses.append("'\(test.query)'→\(test.expect)") }
            if let position, position < 5 { top5 += 1 }
        }
        check(
            "every chosen entry matches its query (\(matched)/\(corpus.cases.count))",
            matched >= requiredMatched, "below \(requiredMatched)")
        check(
            "top-1 cold (\(top1)/\(corpus.cases.count))", top1 >= requiredTop1Cold,
            "below \(requiredTop1Cold); missed \(misses.prefix(8))")
        check(
            "top-5 cold (\(top5)/\(corpus.cases.count))", top5 >= requiredTop5Cold,
            "below \(requiredTop5Cold)")
    }

    // MARK: - Reachability

    static func reachability(_ corpus: Corpus) {
        print("\n# reachability — can using it enough ever make it win")
        var reachable = 0
        var stuck: [String] = []
        for test in corpus.cases where test.unmatched != true {
            let usage = [test.expect: learned(reachablePicks)]
            if rank(test.query, corpus.entries, usage: usage).first?.key == test.expect {
                reachable += 1
            } else {
                stuck.append("'\(test.query)'→\(test.expect)")
            }
        }
        check(
            "every unprotected case is winnable within \(reachablePicks) picks "
                + "(\(reachable)/\(corpus.cases.count))",
            reachable >= requiredReachable, "unreachable: \(stuck)")
        let declared = corpus.cases.filter { $0.protected == true }
        check(
            "the firewall's cost stays enumerated (\(declared.count) protected)",
            declared.count <= allowedProtected && declared.allSatisfy { $0.note != nil },
            "each protected case needs a note naming its escape")

        // Learning must be monotone: more use never demotes the thing being used.
        var regressions = 0
        for test in corpus.cases {
            var wasFirst = false
            for picks in [0, 1, 3, 8, 20, 60] {
                let usage = picks == 0 ? [:] : [test.expect: learned(picks)]
                let first = rank(test.query, corpus.entries, usage: usage).first?.key == test.expect
                if wasFirst && !first { regressions += 1 }
                wasFirst = wasFirst || first
            }
        }
        check("using an entry more never demotes it", regressions == 0, "\(regressions) regressions")

        // One accidental launch must not reorder the deliberate part of the ladder.
        let single = learned(1)
        check(
            "one pick cannot lift anything past a display-name prefix hit",
            SearchRelevance.poolBottom + SearchRelevance.shapeSpan + single < 3_000,
            "one pick is worth \(single)")
    }

    // MARK: - The usage curve

    static func usageCurve() {
        print("\n# usage curve")
        let now = Date()
        func usage(_ count: Int, _ ageDays: Double = 0, share: Double = 1) -> Int {
            LauncherRankingStore.usage(
                count: count, lastUsed: now.addingTimeInterval(-ageDays * 86_400), share: share,
                at: now)
        }
        check(
            "the 49th use is worth more than the 31st", usage(49) > usage(31),
            "31: \(usage(31)), 49: \(usage(49))")
        check(
            "and the 500th more than the 100th", usage(500) > usage(100),
            "100: \(usage(100)), 500: \(usage(500))")
        check(
            "usage never decreases with use",
            (1..<2_000).allSatisfy { usage($0 + 1) >= usage($0) })
        check(
            "usage stays under its ceiling",
            (1...100_000).allSatisfy { usage($0) < SearchRelevance.usageCeiling })
        check("a stale habit decays", usage(50, 90) < usage(50, 0))
        check(
            "a query whose picks are spread thin overrides less",
            usage(10, 0, share: 0.2) < usage(10, 0, share: 1))

        // P1: the firewall, stated as the inequality the whole design rests on.
        check(
            "P1 an exact name hit outranks every weaker match at maximum usage",
            SearchRelevance.protectionFloor
                > SearchRelevance.poolTop + SearchRelevance.shapeSpan
                    + LauncherRankingStore.maximumUsage)
        check(
            "P3 the weakest shown match is still learnable to the top of the pool",
            SearchRelevance.poolBottom + LauncherRankingStore.maximumUsage
                > SearchRelevance.poolTop + SearchRelevance.shapeSpan)
    }

    // MARK: - The empty query

    static func emptyQuery(_ corpus: Corpus) {
        print("\n# the empty query")
        let entries = corpus.entries
        let target = corpus.cases[0].expect
        let ranked = LauncherOrder.within(
            entries, group: \.kind, usage: { $0.key == target ? 2_000 : 0 }, name: \.name)

        check(
            "ranking the empty query is a permutation of the index",
            Set(ranked.map(\.key)) == Set(entries.map(\.key)) && ranked.count == entries.count)
        check(
            "it never moves an entry out of its section",
            zip(entries, ranked).allSatisfy { $0.kind == $1.kind },
            "section order changed")
        let section = ranked.filter { $0.kind == entries.first(where: { $0.key == target })!.kind }
        check(
            "a used entry leads its own section", section.first?.key == target,
            "got \(section.first?.name ?? "none")")
        // Each published slice is already name-sorted, so a run with nothing learned cannot move.
        let alphabetical = entries.map(\.name).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        check(
            "with nothing learned a run falls back to the alphabet",
            LauncherOrder.within(
                entries.sorted { $0.kind < $1.kind }, group: \.kind, usage: { _ in 0 },
                name: \.name
            ).count == alphabetical.count)
    }

    // MARK: - The firewall, on real entries

    static func firewall(_ corpus: Corpus) {
        print("\n# the firewall")
        // An entry named exactly what was typed must survive any rival's habit.
        var violations = 0
        var checked = 0
        for entry in corpus.entries where entry.name.count >= 3 {
            let rivals = corpus.entries.filter { $0.key != entry.key }
            let usage = Dictionary(uniqueKeysWithValues: rivals.map { ($0.key, 2_999) })
            guard let first = rank(entry.name, corpus.entries, usage: usage, limit: 1).first else {
                continue
            }
            checked += 1
            // Another entry may legitimately carry the same name; only a weaker match may not win.
            if first.key != entry.key,
                FuzzyMatch.normalized(first.name) != FuzzyMatch.normalized(entry.name)
            {
                violations += 1
            }
        }
        check(
            "an exactly-typed name beats a saturated rival (\(checked) names)", violations == 0,
            "\(violations) violations")
    }
}
