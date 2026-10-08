import Foundation

/// The blank screen's Spotlight query: the filesystem keeps no last-used date for the index.
enum FileSearchRecents {
    static let candidateLimit = 1_000
    /// A blank screen is a shortlist, not a browser: enough rows to reach, never to scroll far.
    static let limit = 20

    /// Both, because macOS stamps `kMDItemLastUsedDate` on few opens now, and Spotlight sorts on one.
    enum Stamp: String, CaseIterable, Sendable {
        case changed = "kMDItemFSContentChangeDate"
        case used = "kMDItemLastUsedDate"

        /// Spotlight's own literal, so no clock is injected; editing is constant, so it is shorter.
        var window: String {
            switch self {
            case .changed: return "$time.now(-259200)"
            case .used: return "$time.now(-2592000)"
            }
        }
    }

    static func expression(
        stamp: Stamp, excluding exclusions: [String] = [], filter: FileSearchFilter = .all
    ) -> String {
        let touched = "\(stamp.rawValue) > \(stamp.window)"
        let types = filter.spotlightClause.map { [$0] } ?? []
        let excludes = exclusions.map { "kMDItemFSName != \"\(escapeGlob($0))\"cd" }
        return ([touched] + types + excludes).joined(separator: " && ")
    }

    /// The same structural rules the index walk applies, for paths Spotlight hands back.
    static func isExcludedPath(_ path: String, ignoring ignore: FileSearchIgnoreList) -> Bool {
        let structural = path.split(separator: "/").contains { component in
            (component.hasPrefix(".") && component != "." && component != "..")
                || component.lowercased().hasSuffix(".app")
        }
        return structural || ignore.excludes(path: path)
    }

    /// A user pattern keeps its `*`, since that is the one wildcard Spotlight evaluates.
    private static func escapeGlob(_ pattern: String) -> String {
        var escaped = ""
        for character in pattern {
            if character == "\\" || character == "\"" { escaped.append("\\") }
            escaped.append(character)
        }
        return escaped
    }
}
