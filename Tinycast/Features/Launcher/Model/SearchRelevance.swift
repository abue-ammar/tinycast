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

    /// No scalar below U+00AD is `.format`, so ASCII names skip the rebuild and the ICU lookup.
    private static func normalized(_ value: String) -> String {
        guard value.unicodeScalars.contains(where: { $0.value >= 0xAD }) else {
            return value.lowercased()
        }
        guard value.unicodeScalars.contains(where: { $0.properties.generalCategory == .format })
        else { return value.lowercased() }
        let scalars = value.unicodeScalars.filter {
            $0.properties.generalCategory != .format
        }
        return String(String.UnicodeScalarView(scalars)).lowercased()
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

/// Never flatten these into one string — which field matched is what picks the band.
struct SearchFields: Sendable {
    /// The display name, plus anything identifying the entry just as strongly.
    var names: [String]
    /// The user's own alias for the entry; deliberate, so it outranks every vendor field.
    var userAlias: String?
    /// Spotlight's `kMDItemAlternateNames`: `iBooks`, `Codex`, `浏览器`.
    var alternateNames: [String] = []
    /// What provides the entry rather than what it is — the extension a command came from.
    var ownerName: String?
    var bundleID: String?
    var executableName: String?
}

enum SearchRelevance {
    /// One band per field and match strength; a literal hit on a weaker field still wins.
    private enum Band: Int {
        case executableName = 0
        case bundleID = 1
        case alternateNameSubsequence = 2
        case nameSubsequence = 3
        /// Shared by every entry it owns, so a fuzzy hit floods: literal only.
        case ownerName = 4
        case alternateNameLiteral = 5
        case nameLiteral = 6
        case userAlias = 7

        var offset: Int { rawValue * SearchRelevance.bandStride }
    }

    /// Wide enough that a learned boost reorders inside a band, never out of one.
    static let bandStride = 10 * FuzzyMatch.maximumScore

    /// Base relevance from the strongest matching field, or nil when no field matches.
    static func score(query: String, fields: SearchFields) -> Int? {
        score(FuzzyMatch.Query(query), fields: fields)
    }

    /// The folded form: an index folds one query once, not once per entry.
    static func score(_ query: FuzzyMatch.Query, fields: SearchFields) -> Int? {
        // Every entry is equally relevant to an empty query, so no field claims a band.
        guard !query.isEmpty else { return 0 }
        var best: Int?

        func consider(_ candidate: String, literal: Band, subsequence: Band?) {
            guard let match = FuzzyMatch.match(query, candidate: candidate) else { return }
            // A nil subsequence band opts a field out: a loose hit changes which entries appear.
            guard let band = match.tier.isLiteral ? literal : subsequence else { return }
            best = max(best ?? Int.min, band.offset + match.score)
        }

        // Only a hit from the alias's start earns the top band; inside it ranks as a vendor alias.
        if let alias = fields.userAlias, let match = FuzzyMatch.match(query, candidate: alias),
            match.tier.isLiteral
        {
            let band: Band = match.tier.isAnchored ? .userAlias : .alternateNameLiteral
            best = max(best ?? Int.min, band.offset + match.score)
        }
        for name in fields.names {
            consider(name, literal: .nameLiteral, subsequence: .nameSubsequence)
        }
        for alternate in fields.alternateNames {
            consider(alternate, literal: .alternateNameLiteral, subsequence: .alternateNameSubsequence)
        }
        if let ownerName = fields.ownerName {
            consider(ownerName, literal: .ownerName, subsequence: nil)
        }
        if let bundleID = fields.bundleID {
            consider(identifyingPart(of: bundleID), literal: .bundleID, subsequence: nil)
            // A pasted identifier should still resolve, which the trimmed form alone can't do.
            if FuzzyMatch.isExact(query, candidate: bundleID) {
                best = max(best ?? Int.min, Band.bundleID.offset + FuzzyMatch.maximumScore)
            }
        }
        if let executableName = fields.executableName {
            consider(executableName, literal: .executableName, subsequence: nil)
        }
        return best
    }

    /// Drops the leading reverse-DNS component, which prefixes nearly every installed app.
    private static func identifyingPart(of bundleID: String) -> String {
        guard let dot = bundleID.firstIndex(of: ".") else { return bundleID }
        return String(bundleID[bundleID.index(after: dot)...])
    }
}

extension SearchFields {
    /// Spotlight mixes junk in with the real aliases; indexing it makes `app` match all.
    static func usableAlternateNames(
        _ raw: [String], displayName: String, fileName: String
    ) -> [String] {
        let rejected = Set([displayName, fileName].map(strippingAppExtension).map { $0.lowercased() })
        var seen = Set<String>()
        return raw.compactMap { candidate in
            let name = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !isPlaceholder(name) else { return nil }
            let key = strippingAppExtension(name).lowercased()
            guard !key.isEmpty, !rejected.contains(key), seen.insert(key).inserted else { return nil }
            return name
        }
    }

    private static func strippingAppExtension(_ name: String) -> String {
        name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    /// A lone SCREAMING_SNAKE token is an untranslated placeholder, and several ship.
    private static func isPlaceholder(_ name: String) -> Bool {
        name.contains("_") && !name.contains(where: { $0.isLowercase || $0.isWhitespace })
    }
}
