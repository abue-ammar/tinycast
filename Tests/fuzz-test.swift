// Compiles the real scorer, so a scoring change is caught here.
import Foundation

@main
struct FuzzTest {
    // MARK: - Corpus

    struct App {
        let name: String
        var alternates: [String] = []
        var bundleID: String?
        var executable: String?
        var userAlias: String?
        var owner: String?
        /// What the bundle is called on disk, when a rename moved it off the display name.
        var fileName: String?

        /// The sources `AppIndex` hands `EntryNaming`; the aliases below are the shipped ones.
        var sources: EntryNaming.Sources {
            var sources = EntryNaming.Sources(name: name)
            sources.strongNames = [fileName].compactMap { $0 }
            sources.translations = alternates
            sources.ownerName = owner
            sources.bundleID = bundleID
            sources.executableName = executable
            return sources
        }

        /// Everything the alias list carries beyond the display name, as `.translation` text.
        var translations: [String] {
            EntryNaming.aliases(for: sources).filter { $0.role == .translation }.map(\.text)
        }

        /// The shipped lowering, plus the user alias `AppIndex.rank` splices in.
        var fields: SearchFields {
            var aliases = EntryNaming.aliases(for: sources)
            if let userAlias { aliases.append(.userAlias(userAlias)) }
            return SearchFields(aliases)
        }
    }

    // Alternate names taken verbatim from real kMDItemAlternateNames output, junk included.
    static let apps: [App] = [
        App(name: "Google Chrome", alternates: ["Google Chrome.app"], bundleID: "com.google.Chrome"),
        App(name: "Chess", alternates: ["Chess.app"], bundleID: "com.apple.Chess"),
        App(name: "Time Machine", bundleID: "com.apple.backup.launcher"),
        App(
            name: "Safari", alternates: ["浏览器", "browser", "사파리", "Safari.app"],
            bundleID: "com.apple.Safari"),
        App(name: "Bluetooth File Exchange"),
        App(name: "Screenshot"),
        App(name: "Screen Sharing"),
        App(
            name: "Visual Studio Code", bundleID: "com.microsoft.VSCode",
            executable: "Electron"),
        App(name: "Photos", bundleID: "com.apple.Photos"),
        App(name: "App Store", bundleID: "com.apple.AppStore"),
        App(
            name: "System Settings",
            alternates: ["Preferences", "Settings", "System Preferences", "System Settings.app"],
            bundleID: "com.apple.systempreferences"),
        App(name: "Calendar", alternates: ["iCal", "Calendar.app"], bundleID: "com.apple.iCal"),
        App(name: "Terminal", bundleID: "com.apple.Terminal"),
        App(name: "WhatsApp", bundleID: "net.whatsapp.WhatsApp"),
        App(name: "Wick"),
        App(name: "ChatGPT", alternates: ["Codex", "ChatGPT.app"], bundleID: "com.openai.codex"),
        // Nothing named "Codex" — its display name merely contains c-o-d-e…x as a subsequence.
        App(name: "Code Explorer"),
        App(name: "Books", alternates: ["Apple Books", "iBooks", "Books.app"]),
        App(name: "Contacts", alternates: ["Address Book", "Contacts.app"]),
        // Ships an untranslated localization placeholder — see EntryNaming.usable.
        App(name: "Maps", alternates: ["ALTERNATE_NAME_1", "Maps.app"]),
        // Alternate that only repeats the display name; contributes nothing.
        App(name: "Image Playground", alternates: ["Image Playground", "Image Playground.app"]),
        // The corpus entries with user aliases, so the property loop exercises the alias bands.
        App(name: "Figma", userAlias: "fg"),
        // The band-7 overreach repro: `term` inside `iterm` must not beat Terminal's own prefix.
        App(name: "Kitty", userAlias: "iterm"),
        // Extension commands; "Chess" collides with a real app on purpose, which must still win.
        App(name: "Search Icons", owner: "Lucide"),
        App(name: "Browse Categories", owner: "Lucide"),
        App(name: "New Game", owner: "Chess"),
        // The localized names. None of these is findable in ASCII by its own display name.
        App(name: "微信", bundleID: "com.tencent.xinWeChat"),
        App(name: "网易云音乐", bundleID: "com.netease.163music"),
        App(name: "Телеграм", bundleID: "org.telegram.desktop"),
        App(name: "Café Noir"),
        // Latin, but with a non-ASCII scalar in it — must not mint "acc" as a searchable alias.
        App(name: "Adobe — Creative Cloud"),
        // The rename: same bundle in another folder, so the display name never changed.
        App(name: "Slack", bundleID: "com.tinyspeck.slackmacgap", fileName: "Work Chat")
    ]

    static func app(_ name: String) -> App { apps.first { $0.name == name }! }

    /// The table value a score was built from — the largest cell it could have come from.
    static func cellOf(_ score: Int) -> Int {
        SearchAlias.Role.allCases
            .flatMap { role in FuzzyMatch.Tier.allCases.compactMap { SearchRelevance.cell(role, $0) } }
            .filter { $0 <= score }.max() ?? 0
    }

    static func score(_ query: String, _ name: String) -> Int? {
        SearchRelevance.quality(query: query, fields: app(name).fields)
    }

    /// Mirrors AppIndex.rank: strongest field, learned boost, alphabetical tiebreak.
    /// The shipped fold, so this harness cannot drift from what `AppIndex.rank` does.
    static func rank(_ query: String, boosts: [String: Int] = [:]) -> [String] {
        LauncherOrder.ranked(
            apps, query: FuzzyMatch.Query(query), limit: apps.count, fields: \.fields,
            usage: { boosts[$0.name] ?? 0 }, name: \.name
        ).map(\.name)
    }

    static func above(_ ranked: [String], _ winner: String, _ loser: String) -> Bool {
        guard let w = ranked.firstIndex(of: winner), let l = ranked.firstIndex(of: loser) else {
            return false
        }
        return w < l
    }

    // MARK: - Harness

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
        displayNameRanking()
        fieldPriority()
        userAliases()
        ownerNames()
        namingCriteria()
        alternateNameSanitizing()
        identifierFields()
        edgeCases()
        propertyLoop()

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - Display-name ranking (unchanged behavior)

    static func displayNameRanking() {
        print("\n# display-name ranking")

        let chrome = rank("chrome")
        check("'chrome' top is Google Chrome", chrome.first == "Google Chrome", "got \(chrome)")
        check("'chrome' does not include Chess", !chrome.contains("Chess"), "got \(chrome)")

        let ch = rank("ch")
        check("'ch' includes Google Chrome", ch.contains("Google Chrome"), "got \(ch)")
        check("'ch' includes Chess", ch.contains("Chess"))
        check("'ch' ranks Chess (prefix) above Chrome", above(ch, "Chess", "Google Chrome"), "got \(ch)")

        check("'saf' top is Safari", rank("saf").first == "Safari", "got \(rank("saf"))")
        check("'tm' includes Time Machine", rank("tm").contains("Time Machine"), "got \(rank("tm"))")
        check(
            "'code' includes Visual Studio Code", rank("code").contains("Visual Studio Code"),
            "got \(rank("code"))")
        check("'terminal' exact top", rank("terminal").first == "Terminal")
        check("'xyz' matches nothing", rank("xyz").isEmpty, "got \(rank("xyz"))")

        let defaultW = rank("w")
        check(
            "shorter Wick wins the default prefix tie", above(defaultW, "Wick", "WhatsApp"),
            "got \(defaultW)")
        let learnedW = rank("w", boosts: ["WhatsApp": 2_100])
        check(
            "learned boost promotes WhatsApp within the prefix tier",
            above(learnedW, "WhatsApp", "Wick"), "got \(learnedW)")

        let marked = "\u{200E}WhatsApp"
        check(
            "invisible format mark does not demote a prefix match",
            FuzzyMatch.score(query: "w", candidate: marked)
                == FuzzyMatch.score(query: "w", candidate: "WhatsApp"))
        check(
            "learned marked WhatsApp can outrank Wick",
            FuzzyMatch.score(query: "w", candidate: marked)! + 2_100
                > FuzzyMatch.score(query: "w", candidate: "Wick")!)

        check("exact tier", FuzzyMatch.match(query: "chess", candidate: "Chess")?.tier == .exact)
        check("prefix tier", FuzzyMatch.match(query: "che", candidate: "Chess")?.tier == .prefix)
        check(
            "word-start tier",
            FuzzyMatch.match(query: "chrome", candidate: "Google Chrome")?.tier == .wordStart)
        check(
            "substring tier", FuzzyMatch.match(query: "afar", candidate: "Safari")?.tier == .substring)
        check(
            "subsequence tier",
            FuzzyMatch.match(query: "tm", candidate: "Time Machine")?.tier == .subsequence)
        check("no match is nil", FuzzyMatch.match(query: "zzz", candidate: "Chess") == nil)
        check(
            "only subsequence is non-literal",
            [FuzzyMatch.Tier.exact, .prefix, .wordStart, .substring].allSatisfy(\.isLiteral)
                && !FuzzyMatch.Tier.subsequence.isLiteral)
    }

    // MARK: - Field priority

    static func fieldPriority() {
        print("\n# field priority")

        // The decision this feature turns on: an alias the vendor declared beats letter soup.
        let codex = rank("codex")
        check("'codex' finds ChatGPT at all", codex.contains("ChatGPT"), "got \(codex)")
        check(
            "'codex' ranks the exact alias above a subsequence display-name hit",
            above(codex, "ChatGPT", "Code Explorer"), "got \(codex)")

        // ...but a strong display-name match still wins outright.
        let code = rank("code")
        check(
            "'code' ranks the prefix display name above the alias holder",
            above(code, "Code Explorer", "ChatGPT"), "got \(code)")

        let ical = rank("ical")
        check("'ical' finds Calendar by alias", ical.first == "Calendar", "got \(ical)")
        check("'ibooks' finds Books by alias", rank("ibooks").first == "Books", "got \(rank("ibooks"))")
        check(
            "'address book' finds Contacts by alias", rank("address book").first == "Contacts",
            "got \(rank("address book"))")
        check("'browser' finds Safari by alias", rank("browser").first == "Safari", "got \(rank("browser"))")
        check("non-Latin alias matches", rank("浏览器").first == "Safari", "got \(rank("浏览器"))")
        check(
            "'system preferences' finds System Settings by alias",
            rank("system preferences").first == "System Settings")

        // Band ordering, asserted directly on the scores.
        let userAlias = score("fg", "Figma")!
        let nameLiteral = score("chatgpt", "ChatGPT")!
        let aliasLiteral = score("codex", "ChatGPT")!
        let ownerLiteral = score("lucide", "Search Icons")!
        let nameSubsequence = score("codex", "Code Explorer")!
        let aliasSubsequence = score("aplbks", "Books")!
        let identifier = score("openai", "ChatGPT")!
        let ordered = [
            userAlias, nameLiteral, aliasLiteral, ownerLiteral, nameSubsequence, identifier,
            aliasSubsequence
        ]
        check(
            "cells are strictly ordered: user-alias > name > alias > owner > name-fuzzy > id > alias-fuzzy",
            zip(ordered, ordered.dropFirst()).allSatisfy { $0 > $1 }, "got \(ordered)")
        check(
            "a bundle id and an executable name share the technical role",
            score("electron", "Visual Studio Code")! < SearchRelevance.cell(.owner, .wordStart)!
                && identifier < SearchRelevance.cell(.owner, .wordStart)!)
        check(
            "no two of them land in the same cell",
            Set(ordered.map(cellOf)).count == ordered.count, "got \(ordered.map(cellOf))")

        // The strongest field wins; a weaker field on the same entry never drags it down.
        check(
            "Safari's exact display name beats its own alias band",
            score("safari", "Safari")! >= SearchRelevance.cell(.name, .exact)!)
        check(
            "an entry with no matching field scores nil", score("qqqq", "Safari") == nil)
    }

    // MARK: - User aliases

    static func userAliases() {
        print("\n# user aliases")

        let fg = rank("fg")
        check("'fg' finds Figma by user alias", fg.first == "Figma", "got \(fg)")
        check(
            "the user alias sits in the band above the display name",
            score("fg", "Figma")! >= SearchRelevance.cell(.userAlias, .prefix)!)
        check(
            "a user alias outranks another entry's exact display name",
            SearchRelevance.quality(query: "code", fields: SearchFields([.name("Mail"), .userAlias("code")]))!
                > SearchRelevance.quality(query: "code", fields: SearchFields([.name("Code")]))!)
        check(
            "a user alias matches literally: exact, prefix and substring",
            ["mail2", "mai", "ail"].allSatisfy {
                SearchRelevance.quality(
                    query: $0, fields: SearchFields([.name("\u{FFFF}"), .userAlias("mail2")])) != nil
            })
        check(
            "a user alias never subsequence-matches",
            SearchRelevance.quality(
                query: "fga", fields: SearchFields([.name("\u{FFFF}"), .userAlias("figalias")])) == nil)
        let figma = SearchRelevance.quality(query: "figma", fields: app("Figma").fields)!
        check(
            "the strongest field still wins on an aliased entry",
            figma >= SearchRelevance.cell(.name, .exact)! && figma < SearchRelevance.cell(.userAlias, .exact)!
        )

        // Anchoring: only exact and prefix hits earn band 7; inside hits rank with vendor aliases.
        let term = rank("term")
        check(
            "an inside alias hit does not beat another entry's own prefix",
            above(term, "Terminal", "Kitty"), "got \(term)")
        check("...but the aliased entry is still findable", term.contains("Kitty"), "got \(term)")
        check("an alias prefix hit still ranks first", rank("ite").first == "Kitty", "got \(rank("ite"))")
        let inside = SearchRelevance.quality(
            query: "ail", fields: SearchFields([.name("\u{FFFF}"), .userAlias("mail2")]))!
        check(
            "an inside alias hit ranks in the vendor-alias band",
            inside >= SearchRelevance.cell(.translation, .substring)!
                && inside <= SearchRelevance.cell(.translation, .substring)! + SearchRelevance.shapeSpan)
    }

    // MARK: - Owner names

    static func ownerNames() {
        print("\n# owner names")

        let lucide = rank("lucide")
        check(
            "an extension's title finds every command it ships",
            lucide == ["Browse Categories", "Search Icons"], "got \(lucide)")
        check("a prefix of the title works too", rank("luci") == lucide, "got \(rank("luci"))")
        check(
            "the owner band sits below the display name",
            score("lucide", "Search Icons")! >= SearchRelevance.cell(.owner, .exact)!
                && score("lucide", "Search Icons")! < SearchRelevance.cell(.name, .prefix)!)

        let chess = rank("chess")
        check(
            "an app outranks an extension that took its name", above(chess, "Chess", "New Game"),
            "got \(chess)")
        check(
            "an owner title never subsequence-matches",
            SearchRelevance.quality(
                query: "lcd", fields: SearchFields([.name("\u{FFFF}"), .owner("Lucide")])) == nil)
        check(
            "a literal owner hit still beats another entry's subsequence name hit",
            SearchRelevance.quality(
                query: "lucide", fields: SearchFields([.name("\u{FFFF}"), .owner("Lucide")]))!
                > SearchRelevance.quality(query: "lucide", fields: SearchFields([.name("Lucid Engine")]))!)
        check(
            "the command's own title still wins on the same entry",
            score("search", "Search Icons")! >= SearchRelevance.cell(.name, .prefix)!)
    }

    // MARK: - Naming criteria

    /// One line per naming criterion a user has asked for. **A new complaint is a new row here**,
    /// written before the provider that satisfies it — that is what keeps the ladder from drifting.
    static let criteria: [(query: String, expected: String, criterion: String)] = [
        ("chrome", "Google Chrome", "display name"),
        ("browser", "Safari", "Spotlight alternate name"),
        ("浏览器", "Safari", "the alternate in its own script"),
        ("ical", "Calendar", "a vendor's old name for itself"),
        ("codex", "ChatGPT", "an alternate that is nobody's display name"),
        ("fg", "Figma", "the user's own alias"),
        ("openai", "ChatGPT", "the bundle id's vendor component"),
        ("electron", "Visual Studio Code", "the executable name"),
        ("lucide", "Browse Categories", "the owning extension's title, on all its commands"),
        ("微信", "微信", "a Chinese display name typed in Chinese"),
        ("weixin", "微信", "a Chinese display name typed as pinyin"),
        ("wx", "微信", "a Chinese display name typed as pinyin initials"),
        ("wangyiyunyinle", "网易云音乐", "a longer pinyin reading"),
        ("wyyyl", "网易云音乐", "its initials"),
        ("llq", "Safari", "pinyin initials of a Chinese *alternate* name"),
        ("telegram", "Телеграм", "a Cyrillic display name typed in Latin"),
        ("cafe", "Café Noir", "an accented name typed without the accent"),
        ("café", "Café Noir", "...and with it"),
        ("ｃａｆｅ", "Café Noir", "...and in full-width characters"),
        ("work chat", "Slack", "a renamed bundle, found by the name on disk"),
        ("slack", "Slack", "...which never displaces its real display name")
    ]

    static func namingCriteria() {
        print("\n# naming criteria")
        for (query, expected, criterion) in criteria {
            let ranked = rank(query)
            check("'\(query)' finds \(expected) by \(criterion)", ranked.first == expected, "got \(ranked)")
        }
        check(
            "romanizing an ASCII name adds nothing",
            Self.app("Terminal").translations.isEmpty)
        check(
            "a Latin name carrying a stray non-ASCII scalar romanizes to nothing",
            Self.app("Café Noir").translations.isEmpty
                && Self.app("Adobe — Creative Cloud").translations.isEmpty)
        check(
            "so its initials rank as a plain name subsequence, not as a literal translation",
            score("acc", "Adobe — Creative Cloud")! < SearchRelevance.cell(.owner, .substring)!,
            "got \(score("acc", "Adobe — Creative Cloud")!)")
        check(
            "an unreadable script does not invent a match",
            rank("zzzqqq").isEmpty, "got \(rank("zzzqqq"))")
    }

    // MARK: - Spotlight junk

    static func alternateNameSanitizing() {
        print("\n# alternate-name sanitizing")

        let app = rank("app")
        check("'app' still finds App Store", app.first == "App Store", "got \(app)")
        // The tail is `com.apple.*` ids, which the identifier band keeps below name hits.
        check(
            "'app' matches nothing by display name that isn't a real hit",
            app.filter { score("app", $0)! >= SearchRelevance.cell(.name, .substring)! }
                == ["App Store", "Books", "WhatsApp"],
            "got \(app.filter { score("app", $0)! >= SearchRelevance.cell(.name, .substring)! })")
        check(
            "'.app' alternates are dropped entirely",
            !apps.contains { $0.translations.contains { $0.hasSuffix(".app") } })
        check("'alternate' matches nothing", rank("alternate").isEmpty, "got \(rank("alternate"))")
        check(
            "the ALL_CAPS placeholder is dropped", Self.app("Maps").translations.isEmpty)
        check(
            "an alternate repeating the display name is dropped",
            Self.app("Image Playground").translations.isEmpty)
        check(
            "real aliases survive", Self.app("Books").translations == ["Apple Books", "iBooks"])

        func sanitize(_ raw: [String], _ displayName: String, _ fileName: String) -> [String] {
            EntryNaming.usable(raw, rejecting: [displayName, fileName])
        }
        check(
            "empty and whitespace-only names are dropped",
            sanitize(["", "   ", "\n"], "X", "X.app").isEmpty)
        check(
            "case-insensitive dedupe keeps the first spelling",
            sanitize(["iBooks", "IBOOKS", "ibooks"], "Books", "Books.app") == ["iBooks"])
        check("names are trimmed", sanitize(["  iCal  "], "Calendar", "Calendar.app") == ["iCal"])
        check(
            "a name matching the file name but not the display name is still dropped",
            sanitize(["Music.app"], "Apple Music", "Music.app").isEmpty)
        check(
            "an ALL_CAPS name without an underscore is kept",
            sanitize(["IINA"], "Media Player", "mpv.app") == ["IINA"])
        check(
            "a multi-word name with an underscore is kept",
            sanitize(["My_App Pro"], "X", "X.app") == ["My_App Pro"])
        // Find My on a Portuguese Mac: the system-language name arrives beside the file name.
        check(
            "a system-language name survives when it differs",
            sanitize(["FindMy.app", "Buscar"], "Find My", "FindMy.app") == ["Buscar"])
        check(
            "a system-language name equal to the display name is dropped",
            sanitize(["FindMy.app", "Find My"], "Find My", "FindMy.app").isEmpty)
    }

    // MARK: - Identifier fields

    static func identifierFields() {
        print("\n# identifier fields")

        check("bundle-id vendor component matches", rank("openai").contains("ChatGPT"))
        check("the trimmed bundle id matches as a prefix", rank("openai.co").contains("ChatGPT"))
        check("a pasted full bundle id matches", rank("com.openai.codex").contains("ChatGPT"))
        check(
            "bundle ids do not subsequence-match",
            !rank("cop").contains("ChatGPT"), "got \(rank("cop"))")
        check(
            "a short query does not drag in every reverse-DNS id",
            !rank("cml").contains("Photos"), "got \(rank("cml"))")
        // These still hit display names, so nothing may land in the identifier band.
        // `technical` no longer sits under every human role, so "an id-only hit" is a question
        // about which alias matched, not about where the score landed.
        func identifierHits(_ query: String) -> [String] {
            rank(query).filter { name in
                let fields = Self.app(name).fields
                let human = SearchFields(fields.aliases.filter { $0.role != .technical })
                return SearchRelevance.quality(query: query, fields: human) == nil
            }
        }
        check(
            "'com' matches nothing by bundle id", identifierHits("com").isEmpty,
            "got \(identifierHits("com"))")
        check(
            "'co' matches nothing by bundle id", identifierHits("co").isEmpty, "got \(identifierHits("co"))")
        check("'com.' matches nothing by bundle id", identifierHits("com.").isEmpty)
        check(
            "a bundle id with no dot still matches",
            SearchRelevance.quality(query: "solo", fields: SearchFields([.name("X"), .technical("solo")]))
                != nil)
        check("executable name matches literally", rank("electron").contains("Visual Studio Code"))
        check(
            "executable name does not subsequence-match",
            !rank("etn").contains("Visual Studio Code"), "got \(rank("etn"))")

        let noID = SearchFields([.name("Solo")])
        check(
            "an entry with no bundle id or executable still matches on its name",
            SearchRelevance.quality(query: "solo", fields: noID) != nil)
        check("...and matches nothing else", SearchRelevance.quality(query: "com", fields: noID) == nil)
    }

    // MARK: - Edge cases

    static func edgeCases() {
        print("\n# edge cases")

        let fields = app("Safari").fields
        check("empty query scores 0", SearchRelevance.quality(query: "", fields: fields) == 0)
        check(
            "empty query never returns nil for any entry",
            apps.allSatisfy { SearchRelevance.quality(query: "", fields: $0.fields) != nil })
        check(
            "a query longer than every candidate matches nothing",
            rank(String(repeating: "z", count: 500)).isEmpty)
        check("emoji query does not trap", rank("🙂🙃") == [])
        check(
            "an RTL query does not trap",
            SearchRelevance.quality(query: "\u{202E}safari\u{202C}", fields: fields) != nil)
        check(
            "a format-scalar-only query is treated as empty",
            SearchRelevance.quality(query: "\u{200E}", fields: fields) == 0)
        check(
            "an entry with every field empty matches nothing",
            SearchRelevance.quality(query: "x", fields: SearchFields()) == nil)
        check(
            "a snippet keyword ranks at display-name strength",
            SearchRelevance.quality(
                query: "sig", fields: SearchFields([.name("Signature Block"), .name("sig")]))!
                >= SearchRelevance.cell(.name, .exact)!)

        check(
            "ranking is deterministic across repeats",
            (0..<50).allSatisfy { _ in rank("s") == rank("s") })
        // P1: the one gap learning may never close, stated over the published constants.
        check(
            "P1 an exact name hit survives any rival's habit",
            SearchRelevance.protectionFloor
                > SearchRelevance.poolTop + SearchRelevance.shapeSpan + UsageCeiling)
        check(
            "P2 shape orders inside a cell and never leaves it",
            SearchRelevance.shapeSpan < 100)
        check(
            "P3 the weakest shown match is learnable to the top of the pool",
            SearchRelevance.poolBottom + UsageCeiling
                > SearchRelevance.poolTop + SearchRelevance.shapeSpan)
    }

    /// Mirrors LauncherRankingStore.maximumUsage; Tests/ranking-test.swift asserts the real one.
    static let UsageCeiling = SearchRelevance.usageCeiling - 1

    // MARK: - Randomized property loop

    /// Seeded so a failure reproduces exactly rather than vanishing on the next run.
    struct Random {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state >> 16
        }
        mutating func int(_ bound: Int) -> Int { bound <= 0 ? 0 : Int(next() % UInt64(bound)) }
        mutating func element<T>(_ xs: [T]) -> T { xs[int(xs.count)] }
    }

    static func propertyLoop() {
        print("\n# randomized property loop")

        let alphabet = Array("abcdefghijklmnopqrstuvwxyz .-_0123456789浏览器사파리🙂\u{200E}\u{0301}")
        let allText = apps.flatMap { app -> [String] in
            [app.name] + app.alternates + app.translations
                + [app.bundleID, app.executable, app.userAlias, app.owner, app.fileName]
                .compactMap { $0 }
        }
        // Every value the closed table can produce; a score must be one of these plus a shape.
        let cells = SearchAlias.Role.allCases.flatMap { role in
            FuzzyMatch.Tier.allCases.compactMap { SearchRelevance.cell(role, $0) }
        }
        var rng = Random(seed: 0x5EED_1234_ABCD_0001)

        var bandViolations = 0
        var nondeterministic = 0
        var unstableOrder = 0
        var boostCrossedBand = 0
        var matched = 0
        let iterations = 100_000

        for i in 0..<iterations {
            // Three query shapes: a real slice, a scrambled subsequence, and junk.
            let query: String
            switch i % 3 {
            case 0:
                let source = Array(rng.element(allText))
                let start = rng.int(max(1, source.count))
                let length = 1 + rng.int(max(1, source.count - start))
                query = String(source[start..<min(source.count, start + length)])
            case 1:
                let source = Array(rng.element(allText))
                query = String(source.compactMap { rng.int(3) == 0 ? $0 : nil })
            default:
                query = String((0..<(1 + rng.int(8))).map { _ in rng.element(alphabet) })
            }

            for app in apps {
                let fields = app.fields
                guard let score = SearchRelevance.quality(query: query, fields: fields) else { continue }
                matched += 1

                // Every score is one cell plus a shape, and usage may never lift it past P1.
                // A query that folds away claims no cell; every real one is a cell plus a shape.
                if !FuzzyMatch.Query(query).isEmpty,
                    !cells.contains(where: {
                        score - $0 >= 0 && score - $0 <= SearchRelevance.shapeSpan
                    })
                {
                    bandViolations += 1
                }
                if score < SearchRelevance.protectionFloor,
                    score + UsageCeiling >= SearchRelevance.protectionFloor
                {
                    boostCrossedBand += 1
                }
                if SearchRelevance.quality(query: query, fields: fields) != score { nondeterministic += 1 }
            }

            if i % 97 == 0, rank(query) != rank(query) { unstableOrder += 1 }
        }

        check(
            "every score is one cell plus a shape", bandViolations == 0,
            "\(bandViolations) violations")
        check(
            "the max learned usage never crosses the firewall", boostCrossedBand == 0,
            "\(boostCrossedBand) crossings")
        check("scoring is deterministic", nondeterministic == 0, "\(nondeterministic) mismatches")
        check("rank order is stable", unstableOrder == 0, "\(unstableOrder) unstable")
        check(
            "the loop actually exercised matches", matched > iterations / 10,
            "only \(matched) matches over \(iterations) queries")

        // The band ordering must hold for every pair of fields, not just the sampled corpus.
        var inversions = 0
        var rng2 = Random(seed: 0x5EED_1234_ABCD_0002)
        for _ in 0..<20_000 {
            let text = rng2.element(allText)
            let asName: SearchFields = [.name(text)]
            let asUserAlias: SearchFields = [.name("\u{FFFF}"), .userAlias(text)]
            let asAlternate: SearchFields = [.name("\u{FFFF}"), .translation(text)]
            let asOwner: SearchFields = [.name("\u{FFFF}"), .owner(text)]
            let asTechnical: SearchFields = [.name("\u{FFFF}"), .technical(text)]
            let source = Array(text)
            let start = rng2.int(max(1, source.count))
            let query = String(source[start..<min(source.count, start + 1 + rng2.int(6))])
            guard !query.isEmpty,
                let name = SearchRelevance.quality(query: query, fields: asName)
            else { continue }
            let userAlias = SearchRelevance.quality(query: query, fields: asUserAlias)
            let alternate = SearchRelevance.quality(query: query, fields: asAlternate)
            let owner = SearchRelevance.quality(query: query, fields: asOwner)
            let technical = SearchRelevance.quality(query: query, fields: asTechnical)
            // Same text, weaker field: an anchored alias outranks the name, an inside hit does not.
            if let userAlias, let tier = FuzzyMatch.match(query: query, candidate: text)?.tier,
                tier.isAnchored ? userAlias <= name : userAlias >= name
            {
                inversions += 1
            }
            if let alternate, alternate >= name { inversions += 1 }
            if let owner, let alternate, owner >= alternate { inversions += 1 }
            if let technical, let owner, technical >= owner { inversions += 1 }
            if let technical, let alternate, technical >= alternate { inversions += 1 }
        }
        check(
            "the same text always scores lower in a weaker field", inversions == 0, "\(inversions) inversions"
        )
    }
}
