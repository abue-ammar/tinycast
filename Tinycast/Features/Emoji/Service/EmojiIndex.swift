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
    }

    private var byGlyph: [String: EmojiEntry] = [:]
    @ObservationIgnored private var searchMemo = Memo<SearchKey, [EmojiEntry]>()
    /// Bumped on each load, so the key above names the catalog it scored.
    private var revision = 0

    var isLoaded: Bool { !entries.isEmpty }

    func load() async {
        let parsed = await Task.detached(priority: .utility) { EmojiCatalog.parse(EmojiData.raw) }.value
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
    func search(_ query: String, limit: Int = 320) -> [EmojiEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return searchMemo.value(for: SearchKey(query: q, revision: revision)) {
            // Penalized just under half a tier, so an equal-quality name match always wins.
            var scored: [ScoredEntry] = []
            for (order, entry) in entries.enumerated() {
                let nameScore = FuzzyMatch.score(query: q, candidate: entry.name)
                var best = nameScore
                if !entry.keywords.isEmpty,
                    let keywordScore = FuzzyMatch.score(query: q, candidate: entry.keywords)
                {
                    best = max(best ?? Int.min, keywordScore - 500)
                }
                if let best { scored.append(ScoredEntry(entry: entry, score: best, order: order)) }
            }
            return
                scored
                .sorted { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }
                .prefix(limit)
                .map(\.entry)
        }
    }
}
