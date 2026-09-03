import Foundation

enum FuzzyMatch {
    /// All but `.subsequence` are literal hits: the query's own characters, contiguous.
    enum Tier: Sendable {
        case exact
        case prefix
        case wordStart
        case substring
        case subsequence

        var isLiteral: Bool { self != .subsequence }
        /// Anchored at the candidate's start: what a short, deliberate field must match.
        var isAnchored: Bool { self == .exact || self == .prefix }
    }

    struct Match: Sendable {
        let tier: Tier
        let score: Int
    }

    /// A query folded once, so ranking doesn't re-fold it for every candidate field.
    struct Query: Sendable {
        fileprivate let text: String
        /// Folded once too: the subsequence pass needs random access on every candidate.
        fileprivate let characters: [Character]
        var isEmpty: Bool { text.isEmpty }

        init(_ raw: String) {
            text = FuzzyMatch.normalized(raw)
            characters = Array(text)
        }
    }

    /// Tiered relevance, or nil; tiers are spaced so a better kind always wins.
    static func match(query: String, candidate: String) -> Match? {
        match(Query(query), candidate: candidate)
    }

    static func match(_ query: Query, candidate: String) -> Match? {
        let q = query.text
        let c = normalized(candidate)
        guard !q.isEmpty else { return Match(tier: .exact, score: 0) }

        if c == q { return Match(tier: .exact, score: 100_000) }
        if c.hasPrefix(q) { return Match(tier: .prefix, score: 90_000 - c.count) }

        if let range = c.range(of: q) {
            let atWordStart = isWordStart(c, range.lowerBound)
            return Match(
                tier: atWordStart ? .wordStart : .substring,
                score: (atWordStart ? 80_000 : 70_000) - c.count)
        }

        guard let sub = subsequenceScore(query.characters, c) else { return nil }
        return Match(tier: .subsequence, score: sub)
    }

    /// Score-only form, for callers that rank one field and don't band by match strength.
    static func score(query: String, candidate: String) -> Int? {
        match(query: query, candidate: candidate)?.score
    }

    /// The folded form, for a caller sweeping many candidates against one query.
    static func score(_ query: Query, candidate: String) -> Int? {
        match(query, candidate: candidate)?.score
    }

    /// Exact-only, for a caller that discards every weaker tier: skips the subsequence walk.
    static func isExact(_ query: Query, candidate: String) -> Bool {
        normalized(candidate) == query.text
    }

    /// The widest score `match` returns; the bands are sized off it so they never overlap.
    static let maximumScore = 100_000

    /// No scalar below U+00AD is `.format` or carries an accent, so ASCII skips ICU entirely.
    private static func normalized(_ value: String) -> String {
        guard value.unicodeScalars.contains(where: { $0.value >= 0xAD }) else {
            return value.lowercased()
        }
        let scalars = value.unicodeScalars.filter { $0.properties.generalCategory != .format }
        // `Café` has to match "cafe" and full-width `Ｃｈｒｏｍｅ` has to match "chrome".
        return String(String.UnicodeScalarView(scalars))
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    private static func isWordStart(_ s: String, _ index: String.Index) -> Bool {
        if index == s.startIndex { return true }
        let before = s[s.index(before: index)]
        return !before.isLetter && !before.isNumber
    }

    /// Walks in place, carrying the previous character: `Array(c)` was an allocation per keystroke.
    private static func subsequenceScore(_ q: [Character], _ c: String) -> Int? {
        var qi = 0
        var score = 0
        var run = 0
        var prev = -2
        var ci = 0
        var previous: Character?
        for ch in c {
            if qi < q.count, ch == q[qi] {
                var bonus = 1
                if ci == prev + 1 {
                    run += 1
                    bonus += run * 3
                } else {
                    run = 0
                }
                if ci == 0 {
                    bonus += 12
                } else if let previous, !previous.isLetter, !previous.isNumber {
                    bonus += 8
                }
                score += bonus
                prev = ci
                qi += 1
                if qi == q.count { break }
            }
            previous = ch
            ci += 1
        }
        guard qi == q.count else { return nil }
        return score
    }
}

/// One string an entry can be found by. Ranking reads `role` and `looseness` and nothing else, so
/// a new naming criterion adds a producer rather than a scoring rule.
struct SearchAlias: Sendable, Hashable {
    /// A closed ladder: a new criterion picks a role from it and never adds a case.
    enum Role: Int, Sendable {
        /// Machine-facing: bundle id, executable name.
        case technical = 0
        /// What provides the entry rather than what it is — the extension a command came from.
        case owner = 1
        /// Another way to say the same name: a localization, an alternate, a romanization.
        case translation = 2
        /// The name the entry is presented under, and anything identifying it just as strongly.
        case name = 3
        /// The user's own word for the entry; deliberate, so it outranks every vendor string.
        case userAlias = 4

        /// The loosest match this role trusts. Shared or machine text floods on a fuzzy hit.
        var looseness: Looseness {
            switch self {
            case .translation, .name: .fuzzy
            case .technical, .owner, .userAlias: .literal
            }
        }
    }

    /// How weak a match an alias will accept. Tightening one is how a flood-prone string opts out.
    enum Looseness: Sendable, Hashable {
        case fuzzy
        case literal
        case exact

        func accepts(_ tier: FuzzyMatch.Tier) -> Bool {
            switch self {
            case .fuzzy: true
            case .literal: tier.isLiteral
            case .exact: tier == .exact
            }
        }
    }

    let text: String
    let role: Role
    let looseness: Looseness

    init(_ text: String, _ role: Role, looseness: Looseness? = nil) {
        self.text = text
        self.role = role
        self.looseness = looseness ?? role.looseness
    }

    static func name(_ text: String) -> Self { Self(text, .name) }
    static func translation(_ text: String) -> Self { Self(text, .translation) }
    static func owner(_ text: String) -> Self { Self(text, .owner) }
    static func technical(_ text: String) -> Self { Self(text, .technical) }
    static func userAlias(_ text: String) -> Self { Self(text, .userAlias) }
}

/// Never flatten these into one string — which alias matched is half of what picks the band.
struct SearchFields: Sendable, Hashable, ExpressibleByArrayLiteral {
    var aliases: [SearchAlias]

    init(_ aliases: [SearchAlias] = []) { self.aliases = aliases }
    init(arrayLiteral elements: SearchAlias...) { aliases = elements }

    mutating func append(_ alias: SearchAlias) { aliases.append(alias) }
}

enum SearchRelevance {
    /// Wide enough that a learned boost reorders inside a band, never out of one.
    static let bandStride = 10 * FuzzyMatch.maximumScore

    /// Keyed on role and match strength, never on which field supplied the text — that is what lets
    /// a new naming criterion reach this table already sorted.
    private static func band(_ role: SearchAlias.Role, isLiteral: Bool) -> Int {
        switch (role, isLiteral) {
        case (.technical, _): 0
        case (.translation, false): 1
        case (.name, false): 2
        case (.owner, _): 3
        case (.translation, true): 4
        case (.name, true): 5
        case (.userAlias, _): 6
        }
    }

    /// One past the strongest band; the property loop asserts no score ever lands above it.
    static let bandCount = 7

    /// Base relevance from the strongest matching alias, or nil when none matches.
    static func score(query: String, fields: SearchFields) -> Int? {
        score(FuzzyMatch.Query(query), fields: fields)
    }

    /// The folded form: an index folds one query once, not once per entry.
    static func score(_ query: FuzzyMatch.Query, fields: SearchFields) -> Int? {
        // Every entry is equally relevant to an empty query, so no alias claims a band.
        guard !query.isEmpty else { return 0 }
        var best: Int?
        for alias in fields.aliases {
            guard let match = FuzzyMatch.match(query, candidate: alias.text),
                alias.looseness.accepts(match.tier)
            else { continue }
            // A user alias earns its own band only from its start; inside, it is a translation.
            let role: SearchAlias.Role =
                alias.role == .userAlias && !match.tier.isAnchored ? .translation : alias.role
            let score = band(role, isLiteral: match.tier.isLiteral) * bandStride + match.score
            best = max(best ?? Int.min, score)
        }
        return best
    }
}
