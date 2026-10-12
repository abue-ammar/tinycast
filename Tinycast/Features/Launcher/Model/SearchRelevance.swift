import Foundation

enum FuzzyMatch {
    enum Tier: Sendable {
        case exact
        case prefix
        case wordStart
        case substring
        case subsequence
    }

    struct Match: Sendable {
        let tier: Tier
        /// Characters into the candidate the hit begins; 0 for both anchored tiers.
        let offset: Int
        let queryLength: Int
        let candidateLength: Int
        /// The subsequence walk's raw bonus total, and 0 for every literal tier.
        let spread: Int

        /// One ordering for a caller ranking a single field, with no role to weigh.
        var score: Int { FuzzyMatch.rawScore(self) }
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

    /// A candidate folded once, for an index that matches the same text against every query.
    struct Candidate: Sendable {
        let text: String
        fileprivate let length: Int

        init(_ raw: String) {
            text = FuzzyMatch.normalized(raw)
            length = text.count
        }
    }

    /// The tier a query hits a candidate at, with the geometry `SearchRelevance.shape` reads.
    static func match(query: String, candidate: String) -> Match? {
        match(Query(query), candidate: candidate)
    }

    static func match(_ query: Query, candidate: String) -> Match? {
        match(query, candidate: Candidate(candidate))
    }

    static func match(_ query: Query, candidate: Candidate) -> Match? {
        let q = query.text
        let c = candidate.text
        let length = candidate.length
        guard !q.isEmpty else {
            return Match(
                tier: .exact, offset: 0, queryLength: 0, candidateLength: length, spread: 0)
        }

        if c == q {
            return Match(
                tier: .exact, offset: 0, queryLength: query.characters.count,
                candidateLength: length, spread: 0)
        }
        if c.hasPrefix(q) {
            return Match(
                tier: .prefix, offset: 0, queryLength: query.characters.count,
                candidateLength: length, spread: 0)
        }
        if let range = c.range(of: q) {
            let offset = c.distance(from: c.startIndex, to: range.lowerBound)
            return Match(
                tier: isWordStart(c, range.lowerBound) ? .wordStart : .substring, offset: offset,
                queryLength: query.characters.count, candidateLength: length, spread: 0)
        }
        guard let spread = subsequenceScore(query.characters, c) else { return nil }
        return Match(
            tier: .subsequence, offset: 0, queryLength: query.characters.count,
            candidateLength: length, spread: spread)
    }

    /// Score-only form, for callers that rank one field and don't band by match strength.
    static func score(query: String, candidate: String) -> Int? {
        match(query: query, candidate: candidate).map(rawScore)
    }

    /// The folded form, for a caller sweeping many candidates against one query.
    static func score(_ query: Query, candidate: String) -> Int? {
        match(query, candidate: candidate).map(rawScore)
    }

    static func score(_ query: Query, candidate: Candidate) -> Int? {
        match(query, candidate: candidate).map(rawScore)
    }

    /// For callers that rank one field and want a single ordering, not a role-aware one.
    fileprivate static func rawScore(_ match: Match) -> Int {
        switch match.tier {
        case .exact: 100_000
        case .prefix: 90_000 - match.candidateLength
        case .wordStart: 80_000 - match.candidateLength
        case .substring: 70_000 - match.candidateLength
        case .subsequence: match.spread
        }
    }

    /// The one fold every search shares: matching, learned-ranking keys and dedup all call it.
    static func normalized(_ value: String) -> String {
        guard value.unicodeScalars.contains(where: { $0.value >= 0xAD }) else {
            return value.lowercased()
        }
        // Composed first, so a Korean or Vietnamese IME's decomposed input folds like typed text.
        let composed = value.precomposedStringWithCanonicalMapping
        let scalars = composed.unicodeScalars.filter { $0.properties.generalCategory != .format }
        return String(String.UnicodeScalarView(scalars)).folding(options: folding, locale: nil)
    }

    /// Locale-independent: a Turkish fold maps "I" to "ı" and orphans every stored key.
    static let folding: String.CompareOptions = [
        .caseInsensitive, .diacriticInsensitive, .widthInsensitive
    ]

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

    /// What a contiguous run from index 0 would score, so `spread` normalizes to a fraction.
    static func referenceSpread(_ queryLength: Int) -> Int {
        guard queryLength > 0 else { return 1 }
        return 13 + (queryLength - 1) + 3 * queryLength * (queryLength - 1) / 2
    }
}

/// One string an entry can be found by; ranking reads `role` and nothing else.
struct SearchAlias: Sendable, Hashable {
    enum Role: Sendable {
        /// What provides the entry rather than what it is: a menu's path, a window's app.
        case owner
        /// The name the entry is presented under.
        case name
    }

    let text: String
    let role: Role

    init(_ text: String, _ role: Role) {
        self.text = text
        self.role = role
    }

    static func name(_ text: String) -> Self { Self(text, .name) }
    static func owner(_ text: String) -> Self { Self(text, .owner) }
}

/// Never flatten these into one string — which alias matched is half of what picks the cell.
struct SearchFields: Sendable, Hashable, ExpressibleByArrayLiteral {
    var aliases: [SearchAlias]

    init(_ aliases: [SearchAlias] = []) { self.aliases = aliases }
    init(arrayLiteral elements: SearchAlias...) { aliases = elements }

    mutating func append(_ alias: SearchAlias) { aliases.append(alias) }
}

/// How well a query fits a menu item or a window: the strongest field's cell, ordered by shape.
enum SearchRelevance {
    /// `shape` orders inside one cell and can never leave it.
    static let shapeSpan = 99

    static func cell(_ role: SearchAlias.Role, _ tier: FuzzyMatch.Tier) -> Int? {
        switch (role, tier) {
        case (.name, .exact): 6_500
        case (.name, .prefix): 3_000
        case (.owner, .exact): 2_500
        case (.name, .wordStart): 2_400
        case (.owner, .prefix): 2_000
        case (.name, .substring): 1_800
        case (.owner, .wordStart): 1_500
        case (.owner, .substring): 1_100
        case (.name, .subsequence): 1_000
        // Every entry an owner provides shares its text, so a subsequence hit would flood.
        case (.owner, .subsequence): nil
        }
    }

    /// Orders candidates inside one cell: how much of the name the query covered, and how early.
    static func shape(_ match: FuzzyMatch.Match) -> Int {
        guard match.candidateLength > 0 else { return 0 }
        let coverage = min(1, Double(match.queryLength) / Double(match.candidateLength))
        // Absolute, not proportional: a hit five characters in is equally deep in any name.
        let positional =
            match.tier == .subsequence
            ? min(1, Double(match.spread) / Double(FuzzyMatch.referenceSpread(match.queryLength)))
            : 1 / (1 + Double(match.offset) / 4)
        return Int((Double(shapeSpan) * (0.6 * coverage + 0.4 * positional)).rounded())
    }

    /// Base relevance from the strongest matching alias, or nil when none matches.
    static func quality(query: String, fields: SearchFields) -> Int? {
        quality(FuzzyMatch.Query(query), fields: fields)
    }

    /// The folded form: an index folds one query once, not once per entry.
    static func quality(_ query: FuzzyMatch.Query, fields: SearchFields) -> Int? {
        // Every entry is equally relevant to an empty query, so no alias claims a cell.
        guard !query.isEmpty else { return 0 }
        var best: Int?
        for alias in fields.aliases {
            guard let match = FuzzyMatch.match(query, candidate: alias.text),
                let cell = cell(alias.role, match.tier)
            else { continue }
            best = max(best ?? Int.min, cell + shape(match))
        }
        return best
    }
}
