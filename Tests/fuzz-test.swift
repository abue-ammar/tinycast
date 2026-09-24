// Compiles the real root-search scorer and comparator, so a ranking change is caught here.
import Foundation

@main
struct FuzzTest {
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
        scorer()
        sensitivity()
        transliteration()
        naming()
        comparator()
        denseIndex()
        suggestions()
        sharedFold()
        properties()
        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - The scorer

    static func outcome(_ query: String, _ target: String) -> LauncherMatch.Outcome? {
        LauncherMatch.match(
            SearchText(query, transliterated: true), in: SearchText(target, transliterated: true))
    }

    static func score(_ query: String, _ target: String) -> Int? {
        guard case .scored(let score, _)? = outcome(query, target) else { return nil }
        return score
    }

    static func scorer() {
        print("# scorer")
        let pinned: [(String, String, Int)] = [
            ("s", "Safari", 4), ("s", "Clipboard History", 2), ("sa", "Safari", 6), ("sa", "Slack", 5),
            ("vsc", "Visual Studio Code", 8), ("gc", "Google Chrome", 6), ("ss", "System Settings", 6),
            ("settings", "System Settings", 17), ("settings", "Tinycast Settings", 17),
            ("sett", "System Settings", 9), ("chrome", "Google Chrome", 13),
            ("chrome", "Chrome Remote Desktop", 14), ("olu", "Set Volume", 6), ("code", "Xcode", 8),
            ("code", "Visual Studio Code", 9), ("sfr", "Safari", 6), ("notes", "Search Notes", 11),
            ("google chrome", "Google-Chrome", 28), ("vs code", "Visual Studio Code", 16)
        ]
        for (query, target, expected) in pinned {
            let got = score(query, target)
            check(
                "'\(query)' scores \(expected) on \(target)", got == expected,
                "got \(String(describing: got))")
        }
        check("an equal name is exact", outcome("brew", "Brew") == .exact)
        check("a missing letter never matches", outcome("xyz", "Safari") == nil)
        check("a query longer than the name never matches", outcome("safarix", "Safari") == nil)
        check("an empty query matches nothing", outcome("", "Safari") == nil)
        check(
            "a query separator with nothing to land on is skipped",
            outcome("vs-code", "vscode") == .scored(score: 14, skipped: 1),
            "got \(String(describing: outcome("vs-code", "vscode")))")
        check(
            "matched separators never push a row past the name",
            outcome("a--", "a---") == .scored(score: 8, skipped: 0))
        check("a camelCase hump starts a word", score("p", "TablePlus") == 3)
        check(
            "…and survives a join",
            SearchText("Search", transliterated: true).joined(
                with: SearchText("OrbStack", transliterated: true)
            )
            .humps == [10])
        check("…but not in a name the fold can shift", score("s", "CaféStack") == 2)
    }

    // MARK: - Sensitivity

    static func passes(_ query: String, _ target: String, _ sensitivity: SearchSensitivity) -> Bool {
        guard let outcome = outcome(query, target) else { return false }
        return sensitivity.accepts(outcome, queryLength: SearchText(query, transliterated: true).units.count)
    }

    static func sensitivity() {
        print("\n# sensitivity")
        check("High turns away letter soup", !passes("olu", "Set Volume", .high))
        check("…which Medium lets through", passes("olu", "Set Volume", .medium))
        check("High turns away a mid-word hit", !passes("code", "Xcode", .high))
        check("…which Medium lets through", passes("code", "Xcode", .medium))
        check("High still finds initials", passes("vsc", "Visual Studio Code", .high))
        check("High still finds a later word", passes("chrome", "Google Chrome", .high))
        check("…and a camelCase one", passes("stack", "OrbStack", .high))
        check("one letter must start a word", !passes("s", "Clipboard History", .medium))
        check("…and does when it does", passes("s", "Clipboard History", .low))
        check("an exact hit passes every level", SearchSensitivity.high.accepts(.exact, queryLength: 99))
        check("Low accepts any alignment", passes("sfr", "Safari", .low))
    }

    // MARK: - Transliteration

    static func latin(_ raw: String) -> String { SearchText(raw, transliterated: true).string }

    static func transliteration() {
        print("\n# transliteration")
        check("Han reads as spaced pinyin", latin("微信") == "wei xin", "got \(latin("微信"))")
        check("…so its initials hit word starts", passes("wx", "微信", .high))
        check("…and the joined reading hits too", passes("weixin", "微信", .high))
        check("…and the name typed in Chinese is exact", outcome("微信", "微信") == .exact)
        check("a longer reading keeps its syllables", latin("网易云音乐") == "wang yi yun yin le")
        check("mixed script keeps the Latin word", latin("Safari浏览器") == "safari liu lan qi")
        check("Cyrillic reads the way users type it", latin("Телеграм") == "telegram")
        check("the kana romanize, the kanji drop", latin("メモ帳") == "memo", "got \(latin("メモ帳"))")
        check("an accent folds away", latin("Café Noir") == "cafe noir")
        check("full-width input folds", latin("ｃａｆｅ") == "cafe")
        check("Latin text is left as folded", latin("Visual Studio Code") == "visual studio code")
        check(
            "invisible format scalars never reach the scorer",
            latin("\u{200E}Safari") == "safari")
    }

    // MARK: - Naming

    static func profile(
        _ name: String, alternates: [String] = [], subtitle: String? = nil, keywords: [String] = []
    ) -> SearchProfile {
        var sources = EntryNaming.Sources(name: name)
        sources.alternateTitles = alternates
        sources.subtitle = subtitle
        sources.keywords = keywords
        return EntryNaming.profile(for: sources)
    }

    static func naming() {
        print("\n# naming")
        let settings = profile(
            "System Settings", alternates: ["System Settings", "系统设置"],
            keywords: ["ALTERNATE_NAME_1", "System Settings", "Preferences"])
        check("an alternate repeating the title is dropped", settings.alternateTitles.count == 1)
        check(
            "an alternate title is folded, never transliterated",
            settings.alternateTitles.first?.string == "系统设置")
        check(
            "a placeholder and a repeated name leave the keywords",
            settings.keywords.map(\.string) == ["preferences"],
            "got \(settings.keywords.map(\.string))")
        let command = profile("Search", subtitle: "Brew")
        check("a subtitle rides along", command.subtitle?.string == "brew")
        check(
            "title and subtitle join both ways as keywords",
            command.keywords.map(\.string) == ["search brew", "brew search"])
        check("a subtitle equal to the title is dropped", profile("Zed", subtitle: "zed").subtitle == nil)
        check("an unbuilt entry matches nothing", SearchProfile.unnamed.title.isEmpty)
    }

    // MARK: - The comparator, rule by rule

    struct Item {
        let name: String
        var alternates: [String] = []
        var subtitle: String?
        var keywords: [String] = []
        var alias: String?
        var frecency: Double = 1
        /// Most recent last, as the store keeps them.
        var terms: [String] = []
        var priority = 3
        var boosted: Set<String> = []

        var profile: SearchProfile {
            FuzzTest.profile(name, alternates: alternates, subtitle: subtitle, keywords: keywords)
        }

        var signals: LauncherOrder.Signals {
            LauncherOrder.Signals(
                alias: alias.map { SearchText($0, transliterated: false) },
                usage: LauncherUsage(frecency: frecency, searchTerms: terms), priority: priority,
                title: name, boostedTerms: boosted)
        }
    }

    static func rank(
        _ query: String, _ items: [Item], sensitivity: SearchSensitivity = .high
    ) -> [String] {
        LauncherOrder.ranked(
            items, query: LauncherOrder.Query(query), sensitivity: sensitivity, limit: 200,
            profile: \.profile, signals: \.signals
        ).map(\.name)
    }

    static func first(_ query: String, _ items: [Item]) -> String? { rank(query, items).first }

    static func comparator() {
        print("\n# comparator")
        check(
            "an exact alias beats an exact title",
            first("fig", [Item(name: "Fig"), Item(name: "Figma", alias: "fig")]) == "Figma")
        check(
            "a boosted term beats a stronger alignment",
            first("chat", [Item(name: "ChatGPT"), Item(name: "AI Chat", boosted: ["ai", "chat"])])
                == "AI Chat")
        check(
            "…until the other entry is the one the user opens more",
            first(
                "chat",
                [
                    Item(name: "ChatGPT", frecency: 300),
                    Item(name: "AI Chat", frecency: 101, boosted: ["chat"])
                ])
                == "ChatGPT")
        check(
            "past three letters an exact title beats any habit",
            first("notes", [Item(name: "Search Notes", frecency: 900, terms: ["notes"]), Item(name: "Notes")])
                == "Notes")
        check(
            "at three letters an exact search term beats an exact title",
            first("not", [Item(name: "Not"), Item(name: "Notes", frecency: 200, terms: ["not"])]) == "Notes")
        check(
            "an exact search term beats a stronger alignment",
            first("sa", [Item(name: "Safari"), Item(name: "Slack", frecency: 150, terms: ["sa"])]) == "Slack")
        check(
            "an exact subtitle lists an extension's commands first",
            first("brew", [Item(name: "Brewer"), Item(name: "Search", subtitle: "Brew")]) == "Search")
        check(
            "an alias prefix beats a stronger alignment",
            first("sp", [Item(name: "Spotify"), Item(name: "Arc", alias: "spaces")]) == "Arc")
        let appearance = Item(name: "Toggle System Appearance", alias: "toggle light / dark")
        check(
            "a later word of an alias finds its entry",
            rank("dark", [Item(name: "Safari"), appearance]) == ["Toggle System Appearance"])
        check(
            "…ranked by its score, so a title prefix still wins",
            rank("dark", [appearance, Item(name: "Darkroom")]) == ["Darkroom", "Toggle System Appearance"])
        check(
            "a mid-word alias hit stays under the sensitivity",
            rank("term", [Item(name: "Ghostty", alias: "myterm")]).isEmpty)
        check(
            "a term the query prefixes reaches back to shorter queries",
            first(
                "s",
                [Item(name: "Slack", frecency: 400), Item(name: "Safari", frecency: 101, terms: ["safari"])])
                == "Safari")
        let fantastical = Item(
            name: "Fantastical", keywords: ["calendar"], frecency: 150, terms: ["cal"])
        check(
            "a term a longer query runs past still counts, three letters or more",
            first("cale", [Item(name: "Calendar"), fantastical]) == "Fantastical")
        var short = fantastical
        short.terms = ["ca"]
        check("…but not from two", first("cale", [Item(name: "Calendar"), short]) == "Calendar")
        check(
            "the stronger alignment wins before usage",
            first("chrome", [Item(name: "Google Chrome", frecency: 800), Item(name: "Chrome Remote Desktop")])
                == "Chrome Remote Desktop")
        check(
            "frecency breaks an equal alignment",
            first("s", [Item(name: "Safari"), Item(name: "Slack", frecency: 200)]) == "Slack")
        check(
            "a title hit beats the same score on a subtitle",
            first("ma", [Item(name: "Search", subtitle: "Maps"), Item(name: "Maps")]) == "Maps")
        check(
            "an app wins the tie a Tinycast command ties it on",
            first(
                "settings",
                [Item(name: "Tinycast Settings", priority: 3), Item(name: "System Settings", priority: 4)])
                == "System Settings")
        check(
            "names compare numerically last",
            rank("item", [Item(name: "Item 10"), Item(name: "Item 2")]) == ["Item 2", "Item 10"])
        check(
            "a keyword finds an entry without ranking it",
            rank("ical", [Item(name: "Calendar", keywords: ["iCal"]), Item(name: "iCal Import")])
                == ["iCal Import", "Calendar"])
        check(
            "an alternate title ranks, where a keyword only finds",
            rank(
                "sys",
                [
                    Item(name: "Utility", keywords: ["sysadmin"]),
                    Item(name: "系统设置", alternates: ["System Settings"])
                ])
                == ["系统设置", "Utility"])
        let usage = LauncherOrder.byUsage(
            [
                Item(name: "Zed"), Item(name: "Arc", alias: "a"), Item(name: "Maps", frecency: 300),
                Item(name: "Mail", priority: 4)
            ],
            signals: \.signals
        ).map(\.name)
        check(
            "the empty list reads frecency, then aliases, then kind, then name",
            usage == ["Maps", "Arc", "Mail", "Zed"], "got \(usage)")
    }

    // MARK: - A dense index

    static let now = Date(timeIntervalSince1970: 2_000_000_000)

    static let apps: [Item] = [
        "Screen Sharing", "Calculator", "Xcode", "Google Chrome", "AirPort Utility", "Notes", "微信",
        "网易云音乐", "Телеграм", "Café Noir"
    ].map { Item(name: $0, priority: 4) }

    /// Synthetic, and dense where names collide. A new complaint is a new case in `denseIndex`.
    static let index: [Item] =
        apps + [
            Item(name: "Safari", alternates: ["浏览器"], priority: 4),
            Item(name: "Slack", alternates: ["Work Chat"], priority: 4),
            Item(
                name: "System Settings", alternates: ["System Preferences", "Preferences", "Settings"],
                priority: 4),
            Item(name: "Calendar", alternates: ["iCal"], priority: 4),
            Item(name: "Contacts", alternates: ["Address Book"], priority: 4),
            Item(name: "Visual Studio Code", keywords: ["Code"], priority: 4),
            Item(name: "Game Center", priority: 1), Item(name: "Sound", priority: 1),
            Item(name: "Tinycast Settings"), Item(name: "Calculator History"),
            Item(name: "AI Chat", boosted: ["ai", "chat"]), Item(name: "Search Files"),
            Item(name: "Search Notes"), Item(name: "Show Notes"), Item(name: "Set Volume"),
            Item(name: "Search", subtitle: "Brew"), Item(name: "Upgrade", subtitle: "Brew"),
            Item(name: "Signature Block", alternates: ["sig"])
        ]

    /// One pick, replayed through the shipped store's own arithmetic.
    static func picking(_ name: String, by query: String, daysAgo: Double = 0) -> [Item] {
        let at = now.addingTimeInterval(-daysAgo * 86_400)
        let visit = LauncherVisit(
            anchor: LauncherRankingStore.anchor(visitedWith: 1, at: at), openedAt: at,
            searchTerms: query.isEmpty ? [] : [LauncherRankingStore.normalize(query)])
        let usage = LauncherRankingStore.usage(of: visit, at: now)
        return index.map { item in
            guard item.name == name else { return item }
            var picked = item
            picked.frecency = usage.frecency
            picked.terms = usage.searchTerms
            return picked
        }
    }

    static func denseIndex() {
        print("\n# a dense index")
        let cases: [(query: String, first: String, why: String)] = [
            ("settings", "System Settings", "Apple's alternate name beats Tinycast Settings"),
            ("sett", "System Settings", "…and so does its prefix"),
            ("preferences", "System Settings", "an old name Apple still declares"),
            ("ical", "Calendar", "a vendor's old name for itself"),
            ("address book", "Contacts", "…two words long"),
            ("work chat", "Slack", "a renamed bundle, by the name on disk"),
            ("vsc", "Visual Studio Code", "initials of a three-word name"),
            ("code", "Visual Studio Code", "a last word, where Xcode only matches mid-word"),
            ("gc", "Google Chrome", "initials, over a pane sharing them"),
            ("calcu", "Calculator", "an app wins the tie with the command named after it"),
            ("ai", "AI Chat", "a boosted term over an app it ties"),
            ("notes", "Notes", "past three letters, an exact title wins"),
            ("cafe", "Café Noir", "an accent typed without it"), ("ｃａｆｅ", "Café Noir", "…full-width"),
            ("微信", "微信", "a Chinese name typed in Chinese"), ("weixin", "微信", "…as pinyin"),
            ("wx", "微信", "…as pinyin initials"), ("wyyyl", "网易云音乐", "…initials of a longer name"),
            ("telegram", "Телеграм", "a Cyrillic name typed in Latin"),
            ("sig", "Signature Block", "a snippet's keyword"),
            ("brew", "Search", "an extension's title lists its commands")
        ]
        for test in cases {
            let ranked = rank(test.query, index)
            check("'\(test.query)' — \(test.why)", ranked.first == test.first, "got \(ranked.prefix(3))")
        }
        check("an alternate title mints no pinyin", !rank("ll", index).contains("Safari"))
        check("High keeps letter soup out", !rank("olu", index).contains("Set Volume"))
        check("a pick is learned for its query", rank("sa", picking("Slack", by: "sa")).first == "Slack")
        check("…and recalled under a shorter one", rank("s", picking("Slack", by: "sa")).first == "Slack")
        check(
            "a stale habit stops steering",
            rank("sa", picking("Slack", by: "sa", daysAgo: 18)).first == "Safari")
        check(
            "initials win once used",
            rank("ss", picking("System Settings", by: "ss")).first == "System Settings")
        check(
            "a launch from the empty list is use too",
            rank("c", picking("Contacts", by: "")).first == "Contacts")
    }

    // MARK: - Suggestions

    static func suggestions() {
        print("\n# suggestions")
        struct Candidate {
            let name: String
            var frecency: Double = 1
            var alias: String?
            var hotKey = false
            var priority: Int?
            var installedMinutesAgo: Double?
        }
        func select(_ candidates: [Candidate]) -> [String] {
            LauncherSuggestions.select(from: candidates, now: now) { candidate in
                LauncherSuggestions.Traits(
                    signals: LauncherOrder.Signals(
                        alias: candidate.alias.map { SearchText($0, transliterated: false) },
                        usage: LauncherUsage(frecency: candidate.frecency, searchTerms: []), priority: 3,
                        title: candidate.name),
                    installedAt: candidate.installedMinutesAgo.map { now.addingTimeInterval(-$0 * 60) },
                    hasHotKey: candidate.hotKey, priority: candidate.priority)
            }.map(\.name)
        }

        let commands = [
            Candidate(name: "Search Files", priority: 70), Candidate(name: "Clipboard History", priority: 80),
            Candidate(name: "My Schedule", priority: 60),
            Candidate(name: "Search Emoji & Symbols", priority: 50),
            Candidate(name: "Create Snippet", priority: 30)
        ]
        check(
            "a new user gets the built-ins, highest priority first",
            select(commands) == [
                "Clipboard History", "Search Files", "My Schedule", "Search Emoji & Symbols", "Create Snippet"
            ])
        let used = [Candidate(name: "Safari", frecency: 40), Candidate(name: "Slack", frecency: 300)]
        check(
            "what the user opens comes first, most frecent first",
            select(used + commands).prefix(3) == ["Slack", "Safari", "Clipboard History"])
        let many = (1...8).map { Candidate(name: "App \($0)", frecency: Double(100 + $0)) }
        check("never more than five", select(many + commands).count == LauncherSuggestions.limit)
        check(
            "a bound shortcut keeps an entry out",
            !select([Candidate(name: "Slack", frecency: 300, hotKey: true)] + commands).contains("Slack"))
        check(
            "the fill skips a built-in the user already aliased",
            select([Candidate(name: "Clipboard History", alias: "cb", priority: 80)]).isEmpty)
        let fresh = [
            Candidate(name: "New One", installedMinutesAgo: 1),
            Candidate(name: "New Two", installedMinutesAgo: 2),
            Candidate(name: "New Three", installedMinutesAgo: 3),
            Candidate(name: "Old", installedMinutesAgo: 30)
        ]
        let picked = select(fresh + used)
        check(
            "up to two fresh installs lead, then the user's habits",
            picked == ["New One", "New Three", "Slack", "Safari"], "got \(picked)")
        check("an install older than five minutes is not fresh", !picked.contains("Old"))
    }

    // MARK: - The fold other searches share

    static func sharedFold() {
        print("\n# shared fold")
        check("exact tier", FuzzyMatch.match(query: "chess", candidate: "Chess")?.tier == .exact)
        check("prefix tier", FuzzyMatch.match(query: "che", candidate: "Chess")?.tier == .prefix)
        check(
            "word-start tier", FuzzyMatch.match(query: "chr", candidate: "Google Chrome")?.tier == .wordStart)
        check("substring tier", FuzzyMatch.match(query: "hes", candidate: "Chess")?.tier == .substring)
        check("subsequence tier", FuzzyMatch.match(query: "css", candidate: "Chess")?.tier == .subsequence)
        check("the fold is width-insensitive", FuzzyMatch.normalized("ｃａｆｅ") == "cafe")
        check(
            "the fold is locale-independent",
            FuzzyMatch.normalized("I") == "i"
                && FuzzyMatch.normalized("I")
                    != "I".folding(options: [.caseInsensitive], locale: Locale(identifier: "tr_TR"))
        )
    }

    // MARK: - Randomized properties

    /// Seeded, so a failure reproduces on the next run instead of vanishing.
    struct SplitMix64: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    static func properties() {
        print("\n# properties")
        let names = [
            "Safari", "System Settings", "Visual Studio Code", "Google Chrome", "Clipboard History",
            "Search Emoji & Symbols", "Tinycast Settings", "Activity Monitor", "Wi-Fi", "Date & Time",
            "Move to Next Display", "1Password 7", "Set Volume to 25%", "微信", "Телеграм"
        ]
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz -.")
        var generator = SplitMix64(seed: 0x5EED_1234_ABCD_0001)
        var nondeterministic = 0
        var widened = 0
        var strayed = 0
        for _ in 0..<20_000 {
            let name = names.randomElement(using: &generator)!
            let length = Int.random(in: 1...6, using: &generator)
            let query = String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
            let first = outcome(query, name)
            if first != outcome(query, name) { nondeterministic += 1 }
            // Extending a query can only narrow what it matches, once it holds a letter to match.
            if first == nil, query.contains(where: \.isLetter), outcome(query + "a", name) != nil {
                widened += 1
            }
            let ceiling = 4 + 3 * (query.utf16.count - 1)
            if case .scored(let score, _)? = first, score < 1 || score > ceiling { strayed += 1 }
        }
        check("scoring is deterministic", nondeterministic == 0, "\(nondeterministic) mismatches")
        check("typing more never widens a match", widened == 0, "\(widened) widened")
        check("a score stays within its alignment's bounds", strayed == 0, "\(strayed) strayed")
    }
}
