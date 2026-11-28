import Foundation
import Testing

@testable import Tinycast

struct FuzzTests {
    @Test(arguments: [
        ("s", "Safari", 4), ("s", "Clipboard History", 2), ("sa", "Safari", 6), ("sa", "Slack", 5),
        ("vsc", "Visual Studio Code", 8), ("gc", "Google Chrome", 6), ("ss", "System Settings", 6),
        ("settings", "System Settings", 17), ("settings", "Tinycast Settings", 17),
        ("sett", "System Settings", 9), ("chrome", "Google Chrome", 13),
        ("chrome", "Chrome Remote Desktop", 14), ("olu", "Set Volume", 6), ("code", "Xcode", 8),
        ("code", "Visual Studio Code", 9), ("sfr", "Safari", 6), ("notes", "Search Notes", 11),
        ("google chrome", "Google-Chrome", 28), ("vs code", "Visual Studio Code", 16),
        ("p", "TablePlus", 3), ("p", "1Password", 3), ("e", "HTMLEditor", 3),
        ("l", "HTMLEditor", 2), ("s", "CaféStack", 2)
    ])
    func theAlignmentProducesThePinnedScore(_ query: String, _ title: String, _ expected: Int) throws {
        let score = match(query, title).flatMap { outcome -> Int? in
            guard case .scored(let score, _) = outcome else { return nil }
            return score
        }
        let alignment = try #require(score)
        #expect(alignment == expected)
    }

    @Test(
        arguments: [
            ("brew", "Brew", .exact), ("微信", "微信", .exact),
            ("xyz", "Safari", nil), ("safarix", "Safari", nil), ("", "Safari", nil),
            ("vs-code", "vscode", .scored(score: 14, skipped: 1)),
            ("a--", "a---", .scored(score: 8, skipped: 0))
        ] as [(String, String, LauncherMatch.Outcome?)])
    func alignmentDistinguishesExactNamesMissingLettersAndSeparators(
        _ query: String, _ title: String, _ expected: LauncherMatch.Outcome?
    ) {
        #expect(match(query, title) == expected)
    }

    @Test func joiningSearchTextPreservesCamelCaseWordStarts() {
        let title = SearchText("Search", transliterated: true)
        let subtitle = SearchText("OrbStack", transliterated: true)
        #expect(title.joined(with: subtitle).humps == [10])
    }

    @Test(
        arguments: [
            ("olu", "Set Volume", .high, false), ("olu", "Set Volume", .medium, true),
            ("code", "Xcode", .high, false), ("code", "Xcode", .medium, true),
            ("pec", "Accessibility Inspector", .default, true),
            ("vsc", "Visual Studio Code", .high, true), ("chrome", "Google Chrome", .high, true),
            ("stack", "OrbStack", .high, true), ("password", "1Password", .high, true),
            ("edit", "BBEdit", .high, true),
            ("s", "Clipboard History", .medium, false), ("s", "Clipboard History", .low, true),
            ("sfr", "Safari", .low, true), ("wx", "微信", .high, true), ("weixin", "微信", .high, true)
        ] as [(String, String, SearchSensitivity, Bool)])
    func sensitivityFiltersTheAlignment(
        _ query: String, _ title: String, _ level: SearchSensitivity, _ accepted: Bool
    ) {
        let queryText = SearchText(query, transliterated: true)
        let result = LauncherMatch.match(queryText, in: SearchText(title, transliterated: true))
        #expect((result.map { level.accepts($0, queryLength: queryText.units.count) } ?? false) == accepted)
    }

    @Test func highSensitivityAcceptsAnExactMatchRegardlessOfLength() {
        #expect(SearchSensitivity.high.accepts(.exact, queryLength: 99))
    }

    @Test(arguments: [
        ("微信", "wei xin"), ("网易云音乐", "wang yi yun yin le"), ("Safari浏览器", "safari liu lan qi"),
        ("Телеграм", "telegram"), ("メモ帳", "memo"), ("Café Noir", "cafe noir"), ("ｃａｆｅ", "cafe"),
        ("Visual Studio Code", "visual studio code"), ("\u{200E}Safari", "safari")
    ])
    func searchTextFoldsAndRomanizesNames(_ name: String, _ expected: String) {
        #expect(SearchText(name, transliterated: true).string == expected)
    }

    @Test func profileDropsRepeatedNamesAndPlaceholdersAndKeepsAlternateScripts() throws {
        let settings = Entry(
            "System Settings", alternates: ["System Settings", "系统设置"],
            keywords: ["ALTERNATE_NAME_1", "System Settings", "Preferences"]
        ).profile
        #expect(settings.alternateTitles.count == 1)
        let alternate = try #require(settings.alternateTitles.first)
        #expect(alternate.string == "系统设置")
        #expect(settings.keywords.map(\.string) == ["preferences"])
    }

    @Test func aDistinctSubtitleIsSearchableInBothOrders() throws {
        let command = Entry("Search", subtitle: "Brew").profile
        let source = try #require(command.subtitle)
        #expect(source.string == "brew")
        #expect(command.keywords.map(\.string) == ["search brew", "brew search"])
        #expect(Entry("Zed", subtitle: "zed").profile.subtitle == nil)
        #expect(SearchProfile.unnamed.title.isEmpty)
    }

    @Test(arguments: [
        ("fig", [Entry("Fig"), Entry("Figma", alias: "fig")], "Figma"),
        ("brew", [Entry("Brewer"), Entry("Search", subtitle: "Brew")], "Search"),
        ("sp", [Entry("Spotify"), Entry("Arc", alias: "spaces")], "Arc"),
        ("ma", [Entry("Search", subtitle: "Maps"), Entry("Maps")], "Maps")
    ])
    func aliasesAndSubtitlesHaveTheirOwnRankingSignals(
        _ query: String, _ entries: [Entry], _ first: String
    ) throws {
        let winner = try #require(ranked(query, entries).first)
        #expect(winner == first)
    }

    @Test func aLaterAliasWordHelpsOnlyWhenItsScoreIsStrongEnough() {
        let appearance = Entry("Toggle System Appearance", alias: "toggle light / dark")
        #expect(ranked("dark", [Entry("Safari"), appearance]) == ["Toggle System Appearance"])
        #expect(ranked("dark", [appearance, Entry("Darkroom")]) == ["Darkroom", "Toggle System Appearance"])
        #expect(ranked("term", [Entry("Ghostty", alias: "myterm")]).isEmpty)
    }

    @Test(arguments: [
        ("chat", [Entry("ChatGPT"), Entry("AI Chat", boosts: ["ai", "chat"])], "AI Chat"),
        (
            "chat", [Entry("ChatGPT", frecency: 300), Entry("AI Chat", frecency: 101, boosts: ["chat"])],
            "ChatGPT"
        ),
        ("notes", [Entry("Search Notes", frecency: 900, terms: ["notes"]), Entry("Notes")], "Notes"),
        ("not", [Entry("Not"), Entry("Notes", frecency: 200, terms: ["not"])], "Notes"),
        ("sa", [Entry("Safari"), Entry("Slack", frecency: 150, terms: ["sa"])], "Slack"),
        ("s", [Entry("Slack", frecency: 400), Entry("Safari", frecency: 101, terms: ["safari"])], "Safari"),
        (
            "cale",
            [Entry("Calendar"), Entry("Fantastical", keywords: ["calendar"], frecency: 150, terms: ["cal"])],
            "Fantastical"
        ),
        (
            "cale",
            [Entry("Calendar"), Entry("Fantastical", keywords: ["calendar"], frecency: 150, terms: ["ca"])],
            "Calendar"
        )
    ])
    func boostsAndLearnedTermsCompeteWithTheName(_ query: String, _ entries: [Entry], _ first: String) throws
    {
        let winner = try #require(ranked(query, entries).first)
        #expect(winner == first)
    }

    @Test(arguments: [
        (
            "chrome", [Entry("Google Chrome", frecency: 800), Entry("Chrome Remote Desktop")],
            "Chrome Remote Desktop"
        ),
        ("s", [Entry("Safari"), Entry("Slack", frecency: 200)], "Slack"),
        ("ap", [Entry("AirPort Utility"), Entry("App Store")], "App Store"),
        ("dev", [Entry("Desk View", priority: 4), Entry("Device Hub", priority: 1)], "Device Hub"),
        ("ap", [Entry("App Store"), Entry("AirPort Utility", frecency: 200)], "AirPort Utility"),
        (
            "settings", [Entry("Tinycast Settings", priority: 3), Entry("System Settings", priority: 4)],
            "System Settings"
        )
    ])
    func alignmentFrecencyAndKindBreakTiesInOrder(_ query: String, _ entries: [Entry], _ first: String) throws
    {
        let winner = try #require(ranked(query, entries).first)
        #expect(winner == first)
    }

    @Test(arguments: [
        ("item", [Entry("Item 10"), Entry("Item 2")], ["Item 2", "Item 10"]),
        ("ical", [Entry("Calendar", keywords: ["iCal"]), Entry("iCal Import")], ["iCal Import", "Calendar"]),
        (
            "sys", [Entry("Utility", keywords: ["sysadmin"]), Entry("系统设置", alternates: ["System Settings"])],
            ["系统设置", "Utility"]
        )
    ])
    func namesAndAlternateTitlesRankWhileKeywordsOnlyFind(
        _ query: String, _ entries: [Entry], _ expected: [String]
    ) {
        #expect(ranked(query, entries) == expected)
    }

    @Test func browseOrderPrefersUsageThenAliasThenKindThenTitle() {
        let entries = [
            Entry("Zed"), Entry("Arc", alias: "a"), Entry("Maps", frecency: 300), Entry("Mail", priority: 4)
        ]
        #expect(
            LauncherOrder.byUsage(entries, signals: \.signals).map(\.name) == ["Maps", "Arc", "Mail", "Zed"])
    }

    @Test(arguments: ["win", "window", "WINDOW", "ｗｉｎｄｏｗ", "wíndow", " \twindow\n"])
    func normalizedCommonPrefixesExpandEveryMatchingCategory(_ query: String) {
        #expect(categoryMatches(query).count == 4)
    }

    @Test(arguments: [
        ("window man", ["window management"]), ("window \t\n man", ["window management"]),
        ("manage", ["window management"]), ("window com", ["window command"]),
        ("lay", ["window layouts", "window layout"])
    ])
    func categoryWordsNarrowExpansion(_ query: String, _ expected: [String]) {
        #expect(categoryMatches(query) == expected)
    }

    @Test(arguments: ["", " \t\n", "w", "wi", "ind", "wnd", "windowx", "window manager"])
    func emptyShortAndNonPrefixQueriesDoNotExpandCategories(_ query: String) {
        #expect(categoryMatches(query).isEmpty)
    }

    @Test func exactShortCategoryNamesAndCanonicalNamesUseTheSameFold() {
        #expect(LauncherOrder.CategoryQuery("AI").matches(FuzzyMatch.Candidate("AI")))
        #expect(LauncherOrder.CategoryQuery(" \nＳＹＳＴＥＭ\tSettings ").name == "system settings")
    }

    @Test(arguments: [
        ("settings", "System Settings"), ("sett", "System Settings"), ("preferences", "System Settings"),
        ("ical", "Calendar"), ("address book", "Contacts"), ("work chat", "Slack"),
        ("vsc", "Visual Studio Code"),
        ("code", "Visual Studio Code"), ("gc", "Google Chrome"), ("calcu", "Calculator"), ("ai", "AI Chat"),
        ("notes", "Notes"), ("cafe", "Café Noir"), ("ｃａｆｅ", "Café Noir"), ("微信", "微信"), ("weixin", "微信"),
        ("wx", "微信"), ("wyyyl", "网易云音乐"), ("telegram", "Телеграм"), ("sig", "Signature Block"),
        ("brew", "Search"), ("window", "Switch Windows")
    ])
    func denseIndex(_ query: String, _ expected: String) throws {
        let winner = try #require(ranked(query, Self.launcherIndex).first)
        #expect(winner == expected)
    }

    @Test(arguments: [("ll", "Safari"), ("olu", "Set Volume")])
    func denseIndexExcludesRomanizedAlternatesAndWeakSubsequences(_ query: String, _ title: String) {
        #expect(!ranked(query, Self.launcherIndex).contains(title))
    }

    @Test(arguments: [
        ("sa", "Slack", "sa", 0.0, "Slack"), ("s", "Slack", "sa", 0.0, "Slack"),
        ("sa", "Slack", "sa", 18.0, "Safari"), ("ss", "System Settings", "ss", 0.0, "System Settings"),
        ("c", "Contacts", "", 0.0, "Contacts")
    ])
    func aRecentPickLearnsTheTypedQueryAndShorterPrefixes(
        _ query: String, _ visitedTitle: String, _ typed: String, _ daysAgo: Double, _ expected: String
    ) throws {
        let visitDate = Self.now.addingTimeInterval(-daysAgo * 86_400)
        let visit = LauncherVisit(
            anchor: LauncherRankingStore.anchor(visitedWith: 1, at: visitDate), openedAt: visitDate,
            searchTerms: typed.isEmpty ? [] : [LauncherRankingStore.normalize(typed)])
        let usage = LauncherRankingStore.usage(of: visit, at: Self.now)
        var entries = Self.launcherIndex
        let index = try #require(entries.firstIndex { $0.name == visitedTitle })
        entries[index].signals.usage = usage
        let winner = try #require(ranked(query, entries).first)
        #expect(winner == expected)
    }

    @Test func defaultsFillSuggestionsByPriorityAfterFrequentlyUsedApps() {
        let commands = shippingSuggestions
        #expect(
            suggestedTitles(commands) == [
                "Clipboard History", "Search Files", "My Schedule", "Search Emoji & Symbols", "Create Snippet"
            ])
        #expect(
            suggestedTitles(usedSuggestions + commands).prefix(3) == ["Slack", "Safari", "Clipboard History"])
    }

    @Test func suggestionsAreCappedAndExcludeShortcutsAndAlreadyAliasedDefaults() {
        let commands = shippingSuggestions
        let apps = (1...8).map { suggestion("App \($0)", frecency: Double(100 + $0)) }
        #expect(suggestedTitles(apps + commands).count == LauncherSuggestions.limit)
        let bound = suggestion("Slack", frecency: 300, hasHotKey: true)
        #expect(!suggestedTitles([bound] + commands).contains("Slack"))
        #expect(suggestedTitles([suggestion("Clipboard History", alias: "cb", priority: 80)]).isEmpty)
    }

    @Test func theFreshInstallSlotsComeBeforeFrequentlyUsedApps() {
        let installs = [
            suggestion("New One", minutesAgo: 1), suggestion("New Two", minutesAgo: 2),
            suggestion("New Three", minutesAgo: 3), suggestion("Old", minutesAgo: 30)
        ]
        let titles = suggestedTitles(installs + usedSuggestions)
        #expect(titles == ["New One", "New Three", "Slack", "Safari"])
        #expect(!titles.contains("Old"))
    }

    @Test(
        arguments: [
            ("chess", "Chess", .exact), ("che", "Chess", .prefix), ("chr", "Google Chrome", .wordStart),
            ("hes", "Chess", .substring), ("css", "Chess", .subsequence)
        ] as [(String, String, FuzzyMatch.Tier)])
    func theSharedMatcherClassifiesEachAlignment(
        _ query: String, _ title: String, _ tier: FuzzyMatch.Tier
    ) throws {
        let hit = try #require(FuzzyMatch.match(query: query, candidate: title))
        #expect(hit.tier == tier)
    }

    @Test func theSharedFoldIgnoresWidthAndLanguage() {
        #expect(FuzzyMatch.normalized("ｃａｆｅ") == "cafe")
        let folded = FuzzyMatch.normalized("I")
        #expect(folded == "i")
        #expect(folded != "I".folding(options: .caseInsensitive, locale: Locale(identifier: "tr_TR")))
    }

    @Test func seededAlignmentsAreDeterministicNarrowAndBounded() throws {
        let titles = [
            "Safari", "System Settings", "Visual Studio Code", "Google Chrome", "Clipboard History",
            "Search Emoji & Symbols", "Tinycast Settings", "Activity Monitor", "Wi-Fi", "Date & Time",
            "Move to Next Display", "1Password 7", "Set Volume to 25%", "微信", "Телеграм"
        ]
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz -.")
        var random = AlignmentSeed()
        var inconsistent = 0
        var widened = 0
        var outOfBounds = 0
        for _ in 0..<20_000 {
            let title = try #require(titles.randomElement(using: &random))
            let length = Int.random(in: 1...6, using: &random)
            let letters = try (0..<length).map { _ in try #require(alphabet.randomElement(using: &random)) }
            let query = String(letters)
            let result = match(query, title)
            if result != match(query, title) { inconsistent += 1 }
            if result == nil, query.contains(where: \.isLetter),
                match(query + "a", title) != nil
            {
                widened += 1
            }
            if case .scored(let score, _)? = result, !(1...(4 + 3 * (query.utf16.count - 1))).contains(score)
            {
                outOfBounds += 1
            }
        }
        #expect(inconsistent == 0)
        #expect(widened == 0)
        #expect(outOfBounds == 0)
    }

    private static let now = Date(timeIntervalSince1970: 2_000_000_000)

    private static let launcherIndex =
        [
            "Screen Sharing", "Calculator", "Xcode", "Google Chrome", "AirPort Utility", "Notes", "微信",
            "网易云音乐", "Телеграм", "Café Noir"
        ].map { Entry($0, priority: 4) } + [
            Entry("Safari", alternates: ["浏览器"], priority: 4),
            Entry("Slack", alternates: ["Work Chat"], priority: 4),
            Entry(
                "System Settings", alternates: ["System Preferences", "Preferences", "Settings"], priority: 4),
            Entry("Calendar", alternates: ["iCal"], priority: 4),
            Entry("Contacts", alternates: ["Address Book"], priority: 4),
            Entry("Visual Studio Code", keywords: ["Code"], priority: 4),
            Entry("Game Center", priority: 1), Entry("Sound", priority: 1),
            Entry("Tinycast Settings"), Entry("Calculator History"), Entry("AI Chat", boosts: ["ai", "chat"]),
            Entry("Search Files"), Entry("Switch Windows"), Entry("Search Notes"), Entry("Show Notes"),
            Entry("Set Volume"),
            Entry("Search", subtitle: "Brew"), Entry("Upgrade", subtitle: "Brew"),
            Entry("Signature Block", alternates: ["sig"])
        ]

    private func match(_ query: String, _ title: String) -> LauncherMatch.Outcome? {
        LauncherMatch.match(
            SearchText(query, transliterated: true), in: SearchText(title, transliterated: true))
    }

    private func ranked(_ query: String, _ candidates: [Entry]) -> [String] {
        LauncherOrder.ranked(
            candidates, query: LauncherOrder.Query(query), sensitivity: .high, limit: 200,
            profile: \.profile, signals: \.signals
        ).map(\.name)
    }

    private func categoryMatches(_ query: String) -> [String] {
        let category = LauncherOrder.CategoryQuery(query)
        return ["Window Management", "Window Command", "Window Layouts", "Window Layout"]
            .map(FuzzyMatch.Candidate.init).filter(category.matches).map(\.text)
    }

    private var shippingSuggestions: [LauncherSuggestions.Traits] {
        [
            suggestion("Search Files", priority: 70), suggestion("Clipboard History", priority: 80),
            suggestion("My Schedule", priority: 60), suggestion("Search Emoji & Symbols", priority: 50),
            suggestion("Create Snippet", priority: 30)
        ]
    }

    private var usedSuggestions: [LauncherSuggestions.Traits] {
        [suggestion("Safari", frecency: 40), suggestion("Slack", frecency: 300)]
    }

    private func suggestion(
        _ title: String, frecency: Double = 1, alias: String? = nil, hasHotKey: Bool = false,
        priority: Int? = nil, minutesAgo: Double? = nil
    ) -> LauncherSuggestions.Traits {
        let entry = Entry(title, alias: alias, frecency: frecency)
        return LauncherSuggestions.Traits(
            signals: entry.signals, installedAt: minutesAgo.map { Self.now.addingTimeInterval(-$0 * 60) },
            hasHotKey: hasHotKey, priority: priority)
    }

    private func suggestedTitles(_ candidates: [LauncherSuggestions.Traits]) -> [String] {
        LauncherSuggestions.select(from: candidates, now: Self.now) { $0 }.map(\.signals.title)
    }

    struct Entry: Sendable {
        let name: String
        let profile: SearchProfile
        var signals: LauncherOrder.Signals

        init(
            _ name: String, alternates: [String] = [], subtitle: String? = nil, keywords: [String] = [],
            alias: String? = nil, frecency: Double = 1, terms: [String] = [], priority: Int = 3,
            boosts: Set<String> = []
        ) {
            self.name = name
            var sources = EntryNaming.Sources(name: name)
            sources.alternateTitles = alternates
            sources.subtitle = subtitle
            sources.keywords = keywords
            profile = EntryNaming.profile(for: sources)
            signals = LauncherOrder.Signals(
                alias: alias.map { SearchText($0, transliterated: false) },
                usage: LauncherUsage(frecency: frecency, searchTerms: terms), priority: priority,
                title: name, boostedTerms: boosts)
        }
    }

    private struct AlignmentSeed: RandomNumberGenerator {
        private var state: UInt64 = 0x5EED_1234_ABCD_0001

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            return mixed ^ (mixed >> 31)
        }
    }
}
