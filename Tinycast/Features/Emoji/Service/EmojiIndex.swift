import Foundation

/// The parsed catalog: sections precomputed at load, search memoized one query deep.
@MainActor
@Observable
final class EmojiIndex {
    private(set) var entries: [EmojiEntry] = []
    private(set) var categorySections: [(category: EmojiCategory, entries: [EmojiEntry])] = []

    /// `order` is the catalog index, the tie-break that keeps equal scores in catalog order.
    private struct ScoredEntry {
        let entry: EmojiEntry
        let score: Int
        let order: Int
    }

    private struct SearchKey: Equatable {
        let query: String
        let revision: Int
        let frequentID: ObjectIdentifier
        let frequentRevision: Int
        let limit: Int
    }

    private var byGlyph: [String: EmojiEntry] = [:]
    @ObservationIgnored private var searchMemo = Memo<SearchKey, [EmojiEntry]>()
    /// Bumped on each load, so the key above names the catalog it scored.
    private var revision = 0

    var isLoaded: Bool { !entries.isEmpty }

    func load(_ raw: String = EmojiData.raw) async {
        let parsed = await Task.detached(priority: .utility) { EmojiCatalog.parse(raw) }.value
        entries = parsed
        var grouped: [EmojiCategory: [EmojiEntry]] = [:]
        for entry in parsed { grouped[entry.category, default: []].append(entry) }
        categorySections = EmojiCategory.allCases.compactMap { category in
            grouped[category].map { (category, $0) }
        }
        byGlyph = Dictionary(parsed.map { ($0.glyph, $0) }, uniquingKeysWith: { first, _ in first })
        revision &+= 1
    }

    func entry(for glyph: String) -> EmojiEntry? { byGlyph[glyph] }

    /// Ranked fuzzy matches over names and keywords; an empty query returns nothing.
    func search(_ query: String, frequent: FrequentEmojiStore, limit: Int = 320) -> [EmojiEntry] {
        let trimmed = FuzzyMatch.normalized(query).trimmingCharacters(in: .whitespacesAndNewlines)
        let unwrapped =
            trimmed.count > 2 && trimmed.first == ":" && trimmed.last == ":"
            ? String(trimmed.dropFirst().dropLast()) : trimmed
        let words = unwrapped.split(whereSeparator: \.isWhitespace).map(String.init)
        let q = words.joined(separator: " ")
        guard !q.isEmpty, limit > 0 else { return [] }
        let key = SearchKey(
            query: q, revision: revision, frequentID: ObjectIdentifier(frequent),
            frequentRevision: frequent.revision, limit: limit)
        return searchMemo.value(for: key) {
            let query = FuzzyMatch.Query(q)
            let terms = words.count > 1 ? words : []
            let frequentGlyphs = frequent.top(Self.frecencyLimit)
            let frecency = Dictionary(
                frequentGlyphs.enumerated().map {
                    ($0.element, Self.frecencyLimit - $0.offset)
                }, uniquingKeysWith: max)
            var scored: [ScoredEntry] = []
            for (order, entry) in entries.enumerated() {
                guard let textScore = Self.textScore(query, terms: terms, entry: entry) else { continue }
                let score = textScore + (frecency[entry.glyph] ?? 0)
                scored.append(ScoredEntry(entry: entry, score: score, order: order))
            }
            return
                scored
                .sorted { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }
                .prefix(limit)
                .map(\.entry)
        }
    }

    /// Just under half a tier, so an equal-quality name match always wins.
    private static let keywordPenalty = 500
    private static let frecencyLimit = 100
    /// A complete leading name word: above an exact keyword, below the exact name.
    private static let leadingWordScore = 95_000
    /// Scattered query words rank below every literal phrase, name-only words first.
    private static let nameWordsScore = 60_000
    private static let mixedWordsScore = 50_000

    private static func textScore(
        _ query: FuzzyMatch.Query, terms: [String], entry: EmojiEntry
    ) -> Int? {
        var nameOnly = true
        if !terms.isEmpty {
            let name = FuzzyMatch.normalized(entry.name)
            let keywords = FuzzyMatch.normalized(entry.keywords)
            for term in terms where !containsWordStart(term, in: name) {
                guard !term.contains(","), containsWordStart(term, in: keywords) else { return nil }
                nameOnly = false
            }
        }

        let nameMatch = FuzzyMatch.match(query, candidate: entry.name)
        if nameMatch?.tier == .exact { return nameMatch?.score }
        var best = nameMatch?.score
        if let nameMatch, nameMatch.tier == .prefix,
            let next = FuzzyMatch.normalized(entry.name).dropFirst(nameMatch.queryLength).first,
            !next.isLetter && !next.isNumber
        {
            best = leadingWordScore - nameMatch.candidateLength
        }
        if !terms.isEmpty {
            let ordered = nameMatch?.tier == .subsequence ? nameMatch?.score ?? 0 : 0
            best = max(best ?? Int.min, (nameOnly ? nameWordsScore : mixedWordsScore) + ordered)
        }
        guard !entry.keywords.isEmpty, FuzzyMatch.score(query, candidate: entry.keywords) != nil
        else { return best }
        for keyword in entry.keywords.split(separator: ",") {
            guard let match = FuzzyMatch.match(query, candidate: String(keyword)) else { continue }
            best = max(best ?? Int.min, min(match.score, leadingWordScore) - keywordPenalty)
            if match.tier == .exact { break }
        }
        return best
    }

    private static func containsWordStart(_ term: String, in candidate: String) -> Bool {
        var start = candidate.startIndex
        while let range = candidate.range(of: term, range: start..<candidate.endIndex) {
            if range.lowerBound == candidate.startIndex { return true }
            let previous = candidate[candidate.index(before: range.lowerBound)]
            if !previous.isLetter && !previous.isNumber { return true }
            start = candidate.index(after: range.lowerBound)
        }
        return false
    }
}
