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

        /// Mirrors AppEntry.searchFields, including the alternate-name sanitizing the scan applies.
        var fields: SearchFields {
            SearchFields(
                names: [name],
                userAlias: userAlias,
                alternateNames: SearchFields.usableAlternateNames(
                    alternates, displayName: name, fileName: name + ".app"),
                ownerName: owner,
                bundleID: bundleID, executableName: executable)
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
        // Ships an untranslated localization placeholder — see SearchFields.usableAlternateNames.
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
        App(name: "New Game", owner: "Chess")
    ]

    static func app(_ name: String) -> App { apps.first { $0.name == name }! }

    static func score(_ query: String, _ name: String) -> Int? {
        SearchRelevance.score(query: query, fields: app(name).fields)
    }

    /// Mirrors AppIndex.rank: strongest field, learned boost, alphabetical tiebreak.
    static func rank(_ query: String, boosts: [String: Int] = [:]) -> [String] {
        apps.compactMap { app -> (String, Int)? in
            guard let s = SearchRelevance.score(query: query, fields: app.fields) else { return nil }
            return (app.name, s + boosts[app.name, default: 0])
        }
        .sorted {
            $0.1 != $1.1
                ? $0.1 > $1.1
                : $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending
        }
        .map(\.0)
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
        let executable = score("electron", "Visual Studio Code")!
        let ordered = [
            userAlias, nameLiteral, aliasLiteral, ownerLiteral, nameSubsequence, aliasSubsequence,
            identifier, executable
        ]
        check(
            "bands are strictly ordered: user-alias > name > alias > owner > name-fuzzy > alias-fuzzy > id > exec",
            zip(ordered, ordered.dropFirst()).allSatisfy { $0 > $1 }, "got \(ordered)")
        check(
            "every band is a whole stride apart",
            zip(ordered, ordered.dropFirst()).allSatisfy {
                $0 - $1 > FuzzyMatch.maximumScore
            }, "got \(ordered)")

        // The strongest field wins; a weaker field on the same entry never drags it down.
        check(
            "Safari's exact display name beats its own alias band",
            score("safari", "Safari")! >= 6 * SearchRelevance.bandStride)
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
            score("fg", "Figma")! >= 7 * SearchRelevance.bandStride)
        check(
            "a user alias outranks another entry's exact display name",
            SearchRelevance.score(query: "code", fields: SearchFields(names: ["Mail"], userAlias: "code"))!
                > SearchRelevance.score(query: "code", fields: SearchFields(names: ["Code"]))!)
        check(
            "a user alias matches literally: exact, prefix and substring",
            ["mail2", "mai", "ail"].allSatisfy {
                SearchRelevance.score(
                    query: $0, fields: SearchFields(names: ["\u{FFFF}"], userAlias: "mail2")) != nil
            })
        check(
            "a user alias never subsequence-matches",
            SearchRelevance.score(
                query: "fga", fields: SearchFields(names: ["\u{FFFF}"], userAlias: "figalias")) == nil)
        let figma = SearchRelevance.score(query: "figma", fields: app("Figma").fields)!
        check(
            "the strongest field still wins on an aliased entry",
            figma >= 6 * SearchRelevance.bandStride && figma < 7 * SearchRelevance.bandStride)

        // Anchoring: only exact and prefix hits earn band 7; inside hits rank with vendor aliases.
        let term = rank("term")
        check(
            "an inside alias hit does not beat another entry's own prefix",
            above(term, "Terminal", "Kitty"), "got \(term)")
        check("...but the aliased entry is still findable", term.contains("Kitty"), "got \(term)")
        check("an alias prefix hit still ranks first", rank("ite").first == "Kitty", "got \(rank("ite"))")
        let inside = SearchRelevance.score(
            query: "ail", fields: SearchFields(names: ["\u{FFFF}"], userAlias: "mail2"))!
        check(
            "an inside alias hit ranks in the vendor-alias band",
            inside >= 5 * SearchRelevance.bandStride && inside < 6 * SearchRelevance.bandStride)
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
            score("lucide", "Search Icons")! >= 4 * SearchRelevance.bandStride
                && score("lucide", "Search Icons")! < 5 * SearchRelevance.bandStride)

        let chess = rank("chess")
        check(
            "an app outranks an extension that took its name", above(chess, "Chess", "New Game"),
            "got \(chess)")
        check(
            "an owner title never subsequence-matches",
            SearchRelevance.score(
                query: "lcd", fields: SearchFields(names: ["\u{FFFF}"], ownerName: "Lucide")) == nil)
        check(
            "a literal owner hit still beats another entry's subsequence name hit",
            SearchRelevance.score(
                query: "lucide", fields: SearchFields(names: ["\u{FFFF}"], ownerName: "Lucide"))!
                > SearchRelevance.score(query: "lucide", fields: SearchFields(names: ["Lucid Engine"]))!)
        check(
            "the command's own title still wins on the same entry",
            score("search", "Search Icons")! >= 6 * SearchRelevance.bandStride)
    }

    // MARK: - Spotlight junk

    static func alternateNameSanitizing() {
        print("\n# alternate-name sanitizing")

        let app = rank("app")
        check("'app' still finds App Store", app.first == "App Store", "got \(app)")
        // The tail is `com.apple.*` ids, which the identifier band keeps below name hits.
        check(
            "'app' matches nothing by display name that isn't a real hit",
            app.filter { score("app", $0)! >= 5 * SearchRelevance.bandStride }
                == ["App Store", "WhatsApp", "Books"], "got \(app)")
        check(
            "'.app' alternates are dropped entirely",
            !apps.contains { $0.fields.alternateNames.contains { $0.hasSuffix(".app") } })
        check("'alternate' matches nothing", rank("alternate").isEmpty, "got \(rank("alternate"))")
        check(
            "the ALL_CAPS placeholder is dropped", Self.app("Maps").fields.alternateNames.isEmpty)
        check(
            "an alternate repeating the display name is dropped",
            Self.app("Image Playground").fields.alternateNames.isEmpty)
        check(
            "real aliases survive", Self.app("Books").fields.alternateNames == ["Apple Books", "iBooks"])

        let sanitize = SearchFields.usableAlternateNames
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
        func identifierHits(_ query: String) -> [String] {
            rank(query).filter { score(query, $0)! < 2 * SearchRelevance.bandStride }
        }
        check(
            "'com' matches nothing by bundle id", identifierHits("com").isEmpty,
            "got \(identifierHits("com"))")
        check(
            "'co' matches nothing by bundle id", identifierHits("co").isEmpty, "got \(identifierHits("co"))")
        check("'com.' matches nothing by bundle id", identifierHits("com.").isEmpty)
        check(
            "a bundle id with no dot still matches",
            SearchRelevance.score(query: "solo", fields: SearchFields(names: ["X"], bundleID: "solo"))
                != nil)
        check("executable name matches literally", rank("electron").contains("Visual Studio Code"))
        check(
            "executable name does not subsequence-match",
            !rank("etn").contains("Visual Studio Code"), "got \(rank("etn"))")

        let noID = SearchFields(names: ["Solo"])
        check(
            "an entry with no bundle id or executable still matches on its name",
            SearchRelevance.score(query: "solo", fields: noID) != nil)
        check("...and matches nothing else", SearchRelevance.score(query: "com", fields: noID) == nil)
    }

    // MARK: - Edge cases

    static func edgeCases() {
        print("\n# edge cases")

        let fields = app("Safari").fields
        check("empty query scores 0", SearchRelevance.score(query: "", fields: fields) == 0)
        check(
            "empty query never returns nil for any entry",
            apps.allSatisfy { SearchRelevance.score(query: "", fields: $0.fields) != nil })
        check(
            "a query longer than every candidate matches nothing",
            rank(String(repeating: "z", count: 500)).isEmpty)
        check("emoji query does not trap", rank("🙂🙃") == [])
        check(
            "an RTL query does not trap",
            SearchRelevance.score(query: "\u{202E}safari\u{202C}", fields: fields) != nil)
        check(
            "a format-scalar-only query is treated as empty",
            SearchRelevance.score(query: "\u{200E}", fields: fields) == 0)
        check(
            "an entry with every field empty matches nothing",
            SearchRelevance.score(query: "x", fields: SearchFields(names: [])) == nil)
        check(
            "a snippet keyword ranks at display-name strength",
            SearchRelevance.score(
                query: "sig", fields: SearchFields(names: ["Signature Block", "sig"]))!
                >= 6 * SearchRelevance.bandStride)

        check(
            "ranking is deterministic across repeats",
            (0..<50).allSatisfy { _ in rank("s") == rank("s") })
        check(
            "the learned boost cap cannot cross a FuzzyMatch tier",
            LauncherRankingBoostCap < 10_000)
        check(
            "the learned boost cap cannot cross a band",
            LauncherRankingBoostCap < SearchRelevance.bandStride - FuzzyMatch.maximumScore)
    }

    /// Mirrors LauncherRankingStore.maximumBoost; Tests/ranking-test.swift asserts the real one.
    static let LauncherRankingBoostCap = 4_500

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
            [app.name] + app.alternates
                + [app.bundleID, app.executable, app.userAlias, app.owner].compactMap { $0 }
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
                query = String(source.enumerated().compactMap { rng.int(3) == 0 ? $0.element : nil })
            default:
                query = String((0..<(1 + rng.int(8))).map { _ in rng.element(alphabet) })
            }

            for app in apps {
                let fields = app.fields
                guard let score = SearchRelevance.score(query: query, fields: fields) else { continue }
                matched += 1

                // Every score sits inside exactly one band, and the boost cap cannot lift it out.
                let band = score / SearchRelevance.bandStride
                let offset = score - band * SearchRelevance.bandStride
                if offset < 0 || offset > FuzzyMatch.maximumScore || band > 7 { bandViolations += 1 }
                if (score + LauncherRankingBoostCap) / SearchRelevance.bandStride != band {
                    boostCrossedBand += 1
                }
                if SearchRelevance.score(query: query, fields: fields) != score { nondeterministic += 1 }
            }

            if i % 97 == 0, rank(query) != rank(query) { unstableOrder += 1 }
        }

        check("scores always sit inside their band", bandViolations == 0, "\(bandViolations) violations")
        check(
            "the max learned boost never lifts a score out of its band", boostCrossedBand == 0,
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
            let asName = SearchFields(names: [text])
            let asUserAlias = SearchFields(names: ["\u{FFFF}"], userAlias: text)
            let asAlternate = SearchFields(names: ["\u{FFFF}"], alternateNames: [text])
            let asOwner = SearchFields(names: ["\u{FFFF}"], ownerName: text)
            let asBundleID = SearchFields(names: ["\u{FFFF}"], bundleID: text)
            let asExecutable = SearchFields(names: ["\u{FFFF}"], executableName: text)
            let source = Array(text)
            let start = rng2.int(max(1, source.count))
            let query = String(source[start..<min(source.count, start + 1 + rng2.int(6))])
            guard !query.isEmpty,
                let name = SearchRelevance.score(query: query, fields: asName)
            else { continue }
            let userAlias = SearchRelevance.score(query: query, fields: asUserAlias)
            let alternate = SearchRelevance.score(query: query, fields: asAlternate)
            let owner = SearchRelevance.score(query: query, fields: asOwner)
            let bundleID = SearchRelevance.score(query: query, fields: asBundleID)
            let executable = SearchRelevance.score(query: query, fields: asExecutable)
            // Same text, weaker field: an anchored alias outranks the name, an inside hit does not.
            if let userAlias, let tier = FuzzyMatch.match(query: query, candidate: text)?.tier,
                tier.isAnchored ? userAlias <= name : userAlias >= name
            {
                inversions += 1
            }
            if let alternate, alternate >= name { inversions += 1 }
            if let owner, let alternate, owner >= alternate { inversions += 1 }
            if let bundleID, let owner, bundleID >= owner { inversions += 1 }
            if let bundleID, let alternate, bundleID >= alternate { inversions += 1 }
            if let executable, let bundleID, executable >= bundleID { inversions += 1 }
        }
        check(
            "the same text always scores lower in a weaker field", inversions == 0, "\(inversions) inversions"
        )
    }
}
