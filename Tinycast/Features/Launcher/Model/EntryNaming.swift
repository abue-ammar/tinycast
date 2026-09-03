import Foundation

/// The one place an entry's searchable names are decided, for every kind alike.
enum EntryNaming {
    /// Everything a producer knows about what its entry is called.
    struct Sources: Sendable, Hashable {
        var name: String
        /// Names identifying the entry as strongly as its own: a snippet's keyword, a rename.
        var strongNames: [String] = []
        /// Other ways to say the same name: localizations, Spotlight alternates, vendor aliases.
        var translations: [String] = []
        /// What provides the entry rather than what it is — the extension a command came from.
        var ownerName: String?
        var bundleID: String?
        var executableName: String?

        init(name: String) { self.name = name }
    }

    /// Every naming criterion this entry carries, lowered to one flat list of tagged aliases.
    static func aliases(for sources: Sources) -> [SearchAlias] {
        let strong = usable(sources.strongNames, rejecting: [sources.name])
        let translations = usable(
            sources.translations, rejecting: [sources.name] + strong)
        let romanized = usable(
            ([sources.name] + strong + translations).flatMap(ScriptRomanization.typedForms),
            rejecting: [sources.name] + strong + translations)

        var aliases: [SearchAlias] = []
        aliases.reserveCapacity(5 + strong.count + translations.count + romanized.count)
        aliases.append(.name(sources.name))
        for text in strong { aliases.append(.name(text)) }
        for text in translations + romanized { aliases.append(.translation(text)) }
        if let owner = sources.ownerName, !owner.isEmpty { aliases.append(.owner(owner)) }
        if let bundleID = sources.bundleID, !bundleID.isEmpty {
            aliases.append(.technical(identifyingPart(of: bundleID)))
            // The whole reverse-DNS id is exact-only: as a prefix, "com" would match every app.
            aliases.append(SearchAlias(bundleID, .technical, looseness: .exact))
        }
        if let executable = sources.executableName,
            executable.caseInsensitiveCompare(sources.name) != .orderedSame
        {
            aliases.append(.technical(executable))
        }
        return aliases
    }

    static func strippingAppExtension(_ name: String) -> String {
        name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    /// Drops the leading reverse-DNS component, which prefixes nearly every installed app.
    static func identifyingPart(of bundleID: String) -> String {
        guard let dot = bundleID.firstIndex(of: ".") else { return bundleID }
        return String(bundleID[bundleID.index(after: dot)...])
    }

    /// Spotlight mixes junk in with the real aliases; indexing it makes `app` match everything.
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
