import Foundation

/// A launcher fallback: the typed query is its input, so it is offered whatever the query says.
enum Fallback: Hashable, Sendable {
    /// The shipped destinations, in the order a fresh install offers them.
    enum Builtin: String, CaseIterable, Sendable {
        case quickAI
        case searchFiles
        case runShellCommand
        case define

        /// Where its name and glyph come from, so a fallback row reads like the command it runs.
        var command: CommandID {
            switch self {
            case .quickAI: return .quickAI
            case .searchFiles: return .searchFiles
            case .runShellCommand: return .runShellCommand
            case .define: return .define
            }
        }
    }

    case builtin(Builtin)
    case quicklink(UUID)

    /// The row's `AppEntry` id, so a stored order outlives a rename and survives a reinstall.
    var id: String {
        switch self {
        case .builtin(let builtin): return builtin.command.rawValue
        case .quicklink(let id): return Quicklink.entryIDPrefix + id.uuidString.lowercased()
        }
    }

    init?(id: String) {
        if let command = CommandID(rawValue: id),
            let builtin = Builtin.allCases.first(where: { $0.command == command })
        {
            self = .builtin(builtin)
        } else if let quicklink = Quicklink.id(fromEntryID: id) {
            self = .quicklink(quicklink)
        } else {
            return nil
        }
    }

    var openVerb: String {
        switch self {
        case .builtin(.quickAI): return String(localized: "Ask Quick AI")
        case .builtin(.searchFiles): return String(localized: "Search Files")
        case .builtin(.runShellCommand): return String(localized: "Run Shell Command")
        case .builtin(.define): return String(localized: "Define Word")
        case .quicklink: return String(localized: "Open Quicklink")
        }
    }

    /// Stored order first, then anything it has never seen — a quicklink added today lands last.
    static func ordered(_ available: [Fallback], by storedIDs: [String]) -> [Fallback] {
        var remaining = Dictionary(available.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let known = storedIDs.compactMap { remaining.removeValue(forKey: $0) }
        return known + available.filter { remaining[$0.id] != nil }
    }

    /// What has earned the lead by recent use, then the rest exactly as `ordered` had them.
    static func ranked(
        _ ordered: [Fallback], by usage: [String: FallbackUsage], at date: Date
    ) -> [Fallback] {
        let leading =
            ordered.enumerated()
            .compactMap { offset, fallback -> (offset: Int, score: Double, fallback: Fallback)? in
                guard let score = usage[fallback.id]?.score(at: date),
                    score >= FallbackUsage.leadingScore
                else { return nil }
                return (offset, score, fallback)
            }
            .sorted { $0.score == $1.score ? $0.offset < $1.offset : $0.score > $1.score }
            .map(\.fallback)
        return leading + ordered.filter { !leading.contains($0) }
    }

    /// The section header. A long query is elided in the middle, so “with…” always survives.
    static func sectionTitle(query: String, limit: Int = 72) -> String {
        guard query.count > limit else { return String(localized: "Use “\(query)” with…") }
        let elided = "\(query.prefix(limit / 2))…\(query.suffix(limit - limit / 2 - 1))"
        return String(localized: "Use “\(elided)” with…")
    }
}

/// How much one fallback has run lately. Never the query: a shell line can hold a secret.
struct FallbackUsage: Codable, Hashable, Sendable {
    /// A week of a new habit overtakes the old one, and one busy day doesn't undo the habit.
    static let halfLife: TimeInterval = 5 * 86_400
    /// Two runs inside a half-life, so one stray run can't change what Return does next time.
    static let leadingScore = 1.5
    /// Past this a run says nothing, which keeps a deleted quicklink's entry from staying forever.
    private static let forgottenScore = 0.01

    private(set) var score: Double
    private(set) var updatedAt: Date

    /// A clock set backwards reads as no time passed, never as a score that grew.
    func score(at date: Date) -> Double {
        score * pow(0.5, max(0, date.timeIntervalSince(updatedAt)) / Self.halfLife)
    }

    static func recordingRun(
        of id: String, in table: [String: FallbackUsage], at date: Date
    ) -> [String: FallbackUsage] {
        var updated = table.filter { $0.value.score(at: date) >= forgottenScore }
        let previous = table[id]?.score(at: date) ?? 0
        updated[id] = FallbackUsage(score: previous + 1, updatedAt: date)
        return updated
    }
}
