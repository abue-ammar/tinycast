import Foundation

/// The one place an entry's searchable names are decided, for every kind alike.
enum EntryNaming {
    /// Everything a producer knows about what its entry is called.
    struct Sources: Sendable, Hashable {
        var name: String
        /// Ranked like the title: a translation, a renamed file, a snippet keyword.
        var alternateTitles: [String] = []
        /// What the entry comes from, shown beside it: an extension's title.
        var subtitle: String?
        /// Found by, never ranked by: a declared name, an extension's keywords.
        var keywords: [String] = []

        init(name: String) { self.name = name }
    }

    static func profile(for sources: Sources) -> SearchProfile {
        let title = SearchText(sources.name, transliterated: true)
        // Folded, never transliterated: these compare against the query as typed.
        let alternates = usable(sources.alternateTitles, rejecting: [sources.name])
            .map { SearchText($0, transliterated: false) }
        let subtitle = sources.subtitle
            .map { SearchText($0, transliterated: true) }
            .flatMap { $0.isEmpty || $0.units == title.units ? nil : $0 }
        var keywords = usable(sources.keywords, rejecting: [sources.name] + sources.alternateTitles)
            .map { SearchText($0, transliterated: true) }
        if let subtitle { keywords += [title.joined(with: subtitle), subtitle.joined(with: title)] }
        return SearchProfile(
            title: title, alternateTitles: alternates, subtitle: subtitle, keywords: keywords)
    }

    static func strippingAppExtension(_ name: String) -> String {
        name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    /// Info.plist lists repeat the name and ship `ALTERNATE_NAME_1` placeholders.
    static func usable(_ raw: [String], rejecting existing: [String]) -> [String] {
        var seen = Set(existing.map { FuzzyMatch.normalized(strippingAppExtension($0)) })
        return raw.compactMap { candidate in
            let name = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !isPlaceholder(name) else { return nil }
            let key = FuzzyMatch.normalized(strippingAppExtension(name))
            guard !key.isEmpty, seen.insert(key).inserted else { return nil }
            return name
        }
    }

    /// A lone SCREAMING_SNAKE token is an untranslated placeholder, and several ship.
    private static func isPlaceholder(_ name: String) -> Bool {
        name.contains("_") && !name.contains(where: { $0.isLowercase || $0.isWhitespace })
    }
}

/// Built by `EntryNaming.profile` alone.
struct SearchProfile: Sendable, Hashable {
    var title: SearchText
    var alternateTitles: [SearchText]
    var subtitle: SearchText?
    /// Match to appear, never to rank.
    var keywords: [SearchText]

    /// What an entry holds before its first index pass: nothing a query can reach.
    static let unnamed = SearchProfile(
        title: SearchText(units: []), alternateTitles: [], subtitle: nil, keywords: [])
}
