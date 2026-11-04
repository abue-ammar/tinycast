import Foundation

@main
@MainActor
struct FallbackTests {
    static var failures = 0
    static var passes = 0

    static func check(_ name: String, _ condition: Bool, _ detail: String = "") {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        }
    }

    static func main() {
        identity()
        ordering()
        ranking()
        usage()
        headers()
        verbs()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Identity

    static func identity() {
        // The id *is* the row's entry id, which is what lets a stored order name a live row.
        for builtin in Fallback.Builtin.allCases {
            let fallback = Fallback.builtin(builtin)
            check(
                "\(builtin.rawValue) is its command's id", fallback.id == builtin.command.rawValue,
                "got \(fallback.id)")
            check(
                "\(builtin.rawValue) round-trips", Fallback(id: fallback.id) == fallback,
                "got \(String(describing: Fallback(id: fallback.id)))")
        }

        let quicklinkID = UUID()
        let quicklink = Fallback.quicklink(quicklinkID)
        check(
            "a quicklink's id is its entry id",
            quicklink.id == Quicklink.entryIDPrefix + quicklinkID.uuidString.lowercased(),
            "got \(quicklink.id)")
        check("a quicklink round-trips", Fallback(id: quicklink.id) == quicklink)

        // Every built-in's id must be distinct, or one would silently take another's stored slot.
        let ids = Set(Fallback.Builtin.allCases.map { Fallback.builtin($0).id })
        check("built-in ids are distinct", ids.count == Fallback.Builtin.allCases.count)

        // A command with no fallback of its own must not resolve to one.
        check("a plain command is not a fallback", Fallback(id: CommandID.about.rawValue) == nil)
        check("nonsense is not a fallback", Fallback(id: "banana") == nil)
        check("a bare uuid is not a fallback", Fallback(id: UUID().uuidString) == nil)
    }

    // MARK: - Ordering

    static func ordering() {
        let ai = Fallback.builtin(.quickAI)
        let files = Fallback.builtin(.searchFiles)
        let shell = Fallback.builtin(.runShellCommand)
        let link = Fallback.quicklink(UUID())

        check(
            "no stored order keeps the offered order",
            Fallback.ordered([ai, files, shell], by: []) == [ai, files, shell])

        check(
            "a stored order is honoured",
            Fallback.ordered([ai, files, shell], by: [shell.id, ai.id, files.id])
                == [shell, ai, files])

        // A quicklink created after the last reorder must land at the end, not vanish.
        check(
            "an unseen fallback lands last",
            Fallback.ordered([ai, link, files], by: [files.id, ai.id]) == [files, ai, link])

        // A deleted quicklink's id is still stored; it must not resurrect or shift its neighbours.
        check(
            "a stored id with nothing behind it is skipped",
            Fallback.ordered([ai, files], by: [link.id, files.id, ai.id]) == [files, ai])

        check("nothing available is nothing offered", Fallback.ordered([], by: [ai.id]).isEmpty)
    }

    // MARK: - Ranking

    static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    static let day: TimeInterval = 86_400

    static func at(_ days: Double) -> Date { start.addingTimeInterval(days * day) }

    /// `perDay` runs spread evenly across `days`, from `from`, so a habit reads as a habit.
    static func runs(
        _ fallback: Fallback, perDay: Int, days: Double, from: Double,
        into table: [String: FallbackUsage] = [:]
    ) -> [String: FallbackUsage] {
        var table = table
        for run in 0..<Int(days * Double(perDay)) {
            let date = at(from + Double(run) / Double(perDay))
            table = FallbackUsage.recordingRun(of: fallback.id, in: table, at: date)
        }
        return table
    }

    static func ranking() {
        let ai = Fallback.builtin(.quickAI)
        let files = Fallback.builtin(.searchFiles)
        let shell = Fallback.builtin(.runShellCommand)
        let define = Fallback.builtin(.define)
        let base = [ai, files, shell, define]

        check(
            "nothing run keeps the arranged order",
            Fallback.ranked(base, by: [:], at: start) == base)

        // The first press must not change what Return does on the next search.
        let once = runs(shell, perDay: 1, days: 1, from: 0)
        check(
            "one stray run leads nothing",
            Fallback.ranked(base, by: once, at: at(1)) == base)

        let twice = runs(shell, perDay: 2, days: 1, from: 0)
        check(
            "two close runs take the lead",
            Fallback.ranked(base, by: twice, at: at(1)) == [shell, ai, files, define])

        // Two runs a month apart are no pattern, however many there have been in total.
        let apart = FallbackUsage.recordingRun(
            of: shell.id, in: once, at: at(30))
        check(
            "two runs a month apart lead nothing",
            Fallback.ranked(base, by: apart, at: at(30)) == base)

        var both = runs(shell, perDay: 3, days: 5, from: 0)
        both = runs(define, perDay: 1, days: 5, from: 0, into: both)
        check(
            "the more used leads the less used",
            Fallback.ranked(base, by: both, at: at(5)) == [shell, define, ai, files])

        // The reader's own arrangement still decides everything nothing has earned.
        check(
            "what has not earned the lead keeps its order",
            Fallback.ranked([files, ai, shell, define], by: both, at: at(5))
                == [shell, define, files, ai])

        let tied = runs(define, perDay: 2, days: 1, from: 0, into: twice)
        check(
            "a tie falls back to the arranged order",
            Fallback.ranked([define, shell], by: tied, at: at(1)) == [define, shell])
        check(
            "a tie reads the same the other way round",
            Fallback.ranked([shell, define], by: tied, at: at(1)) == [shell, define])

        // The reported case: a long AI habit, then only the shell.
        let aiHabit = runs(ai, perDay: 5, days: 30, from: 0)
        let switched = { (days: Double) in
            runs(shell, perDay: 5, days: days, from: 30, into: aiHabit)
        }
        check(
            "the old habit still leads early in a switch",
            Fallback.ranked(base, by: switched(2), at: at(32)).first == ai)
        check(
            "the new habit leads within a week of switching",
            Fallback.ranked(base, by: switched(7), at: at(37)).first == shell)

        // The other direction: recency must not make one busy day look like a new habit.
        let shellHabit = runs(shell, perDay: 5, days: 30, from: 0)
        let burst = runs(ai, perDay: 15, days: 1, from: 30, into: shellHabit)
        check(
            "one busy day does not unseat a habit",
            Fallback.ranked(base, by: burst, at: at(31)).first == shell)

        // Decay is proportional, so time alone can't swap two rows while nothing is run.
        check(
            "a quiet weekend keeps the order",
            Fallback.ranked(base, by: both, at: at(8)) == [shell, define, ai, files])
        check(
            "only the weaker habit lapses when a quiet spell runs on",
            Fallback.ranked(base, by: both, at: at(12)) == [shell, ai, files, define])
        check(
            "a long absence returns to the arranged order",
            Fallback.ranked(base, by: both, at: at(120)) == base)

        // A deleted quicklink's score must not resurrect it or displace a live row.
        let gone = Fallback.quicklink(UUID())
        check(
            "usage with nothing behind it is ignored",
            Fallback.ranked(base, by: runs(gone, perDay: 5, days: 3, from: 0), at: at(3)) == base)
        check(
            "nothing offered is nothing ranked",
            Fallback.ranked([], by: twice, at: at(1)).isEmpty)
    }

    // MARK: - Usage

    static func usage() {
        let shell = Fallback.builtin(.runShellCommand)
        let ai = Fallback.builtin(.quickAI)

        let first = FallbackUsage.recordingRun(of: shell.id, in: [:], at: start)
        let run = first[shell.id]
        check("a first run scores one", run?.score(at: start) == 1)
        check(
            "the score halves over a half-life",
            run?.score(at: start.addingTimeInterval(FallbackUsage.halfLife)) == 0.5)
        check(
            "a clock set backwards never grows the score",
            run?.score(at: at(-10)) == 1)

        let second = FallbackUsage.recordingRun(
            of: shell.id, in: first, at: start.addingTimeInterval(FallbackUsage.halfLife))
        check(
            "a later run adds to what has decayed",
            second[shell.id]?.score(at: start.addingTimeInterval(FallbackUsage.halfLife)) == 1.5)

        // The table is what stays on disk, so a deleted quicklink has to leave it eventually.
        let later = FallbackUsage.recordingRun(of: ai.id, in: first, at: at(365))
        check("a long-stale entry is forgotten", later[shell.id] == nil, "got \(later)")
        check("the run itself is kept", later[ai.id] != nil)

        // The shape on disk is the privacy promise: a shell line may hold a secret.
        let encoded = (try? JSONEncoder().encode(first)).flatMap { String(data: $0, encoding: .utf8) }
        let decoded = (try? JSONEncoder().encode(first)).flatMap {
            try? JSONDecoder().decode([String: FallbackUsage].self, from: $0)
        }
        check("usage round-trips", decoded == first)
        check(
            "usage stores only a score and a time",
            encoded?.contains("query") == false && encoded?.contains("score") == true
                && (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(run)))
                    .flatMap { ($0 as? [String: Any])?.count } == 2,
            "got \(encoded ?? "nil")")
    }

    // MARK: - Header

    static func headers() {
        check(
            "a short query is quoted whole",
            Fallback.sectionTitle(query: "todo") == "Use “todo” with…",
            "got \(Fallback.sectionTitle(query: "todo"))")

        let long = String(repeating: "a", count: 200)
        let title = Fallback.sectionTitle(query: long, limit: 20)
        // The point of the elision: the header must still say what the section is for.
        check("a long query still ends in the verb", title.hasSuffix("” with…"), "got \(title)")
        check("a long query is elided", title.contains("…a"), "got \(title)")
        check("a long query is bounded by the limit", title.count <= 20 + 13, "got \(title.count)")

        // The boundary is exact equality, so a query at the limit is never touched.
        let exact = String(repeating: "b", count: 20)
        check(
            "a query at the limit is kept whole",
            Fallback.sectionTitle(query: exact, limit: 20) == "Use “\(exact)” with…")

        // The shipped limit has to clear a real URL, which is the query this was drawn against.
        let url = "https://github.com/vgnshiyer/py-apple-books.git"
        check(
            "the default limit keeps a repository URL whole",
            Fallback.sectionTitle(query: url) == "Use “\(url)” with…",
            "got \(Fallback.sectionTitle(query: url))")
    }

    // MARK: - Verbs

    static func verbs() {
        var verbs = Fallback.Builtin.allCases.map { Fallback.builtin($0).openVerb }
        verbs.append(Fallback.quicklink(UUID()).openVerb)
        check("every fallback names its own action", verbs.allSatisfy { !$0.isEmpty })
        check("the verbs are distinct", Set(verbs).count == verbs.count, "got \(verbs)")
    }
}
