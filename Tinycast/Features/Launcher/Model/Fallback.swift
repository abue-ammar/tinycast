import Foundation

/// A launcher fallback: the typed query is its input, so it is offered whatever the query says.
enum Fallback: Hashable, Sendable {
    /// The shipped destinations, in the order a fresh install offers them.
    enum Builtin: String, CaseIterable, Sendable {
        case aiChat
        case searchFiles
        case runShellCommand

        /// Where its name and glyph come from, so a fallback row reads like the command it runs.
        var command: CommandID {
            switch self {
            case .aiChat: return .aiChat
            case .searchFiles: return .searchFiles
            case .runShellCommand: return .runShellCommand
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

    /// The footer pill's verb: what ↵ does, in the destination's own words.
    var openVerb: String {
        switch self {
        case .builtin(.aiChat): return "Ask AI Chat"
        case .builtin(.searchFiles): return "Search Files"
        case .builtin(.runShellCommand): return "Run Shell Command"
        case .quicklink: return "Open Quicklink"
        }
    }

    /// Stored order first, then anything it has never seen — a quicklink added today lands last.
    static func ordered(_ available: [Fallback], by storedIDs: [String]) -> [Fallback] {
        var remaining = Dictionary(available.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let known = storedIDs.compactMap { remaining.removeValue(forKey: $0) }
        return known + available.filter { remaining[$0.id] != nil }
    }

    /// The section header. A long query is elided in the middle, so “with…” always survives.
    static func sectionTitle(query: String, limit: Int = 72) -> String {
        guard query.count > limit else { return "Use “\(query)” with…" }
        return "Use “\(query.prefix(limit / 2))…\(query.suffix(limit - limit / 2 - 1))” with…"
    }
}
