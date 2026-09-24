import Foundation

/// The launcher's two orderings, kept pure so a harness ranks the shipped code.
enum LauncherOrder {
    /// Folded once per pass, in both forms the fields compare against.
    struct Query: Sendable {
        /// Titles, subtitles, keywords and search terms compare against the Latin reading.
        let latin: SearchText
        /// Alternate titles and aliases compare against the text as typed.
        let typed: SearchText
        let term: String

        var isEmpty: Bool { typed.isEmpty }

        init(_ raw: String) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            latin = SearchText(trimmed, transliterated: true)
            typed = SearchText(trimmed, transliterated: false)
            term = typed.string
        }
    }

    struct Signals: Sendable {
        var alias: SearchText?
        var usage: LauncherUsage
        /// Which kind wins a full tie; higher first.
        var priority: Int
        var title: String
        /// Queries this entry wins until the user opens a rival more.
        var boostedTerms: Set<String> = []
    }

    static func ranked<Item>(
        _ items: [Item], query: Query, sensitivity: SearchSensitivity, limit: Int,
        profile: (Item) -> SearchProfile, signals: (Item) -> Signals
    ) -> [Item] {
        guard !query.isEmpty else { return [] }
        let scored = items.enumerated().compactMap { position, item -> (Item, Candidate)? in
            let signals = signals(item)
            guard
                let facts = Facts(
                    profile: profile(item), signals: signals, query: query, sensitivity: sensitivity)
            else { return nil }
            return (item, Candidate(facts: facts, signals: signals, position: position))
        }
        let length = query.latin.units.count
        return
            scored
            .sorted { orders($0.1, before: $1.1, length: length) }
            .prefix(limit)
            .map(\.0)
    }

    /// The empty list: most frecent first, then aliased entries, then by kind and name.
    static func byUsage<Item>(_ items: [Item], signals: (Item) -> Signals) -> [Item] {
        items.enumerated()
            .map { ($0.element, Candidate(facts: nil, signals: signals($0.element), position: $0.offset)) }
            .sorted {
                let order = tiebreak($0.1, $1.1)
                return order != 0 ? order < 0 : $0.1.position < $1.1.position
            }
            .map(\.0)
    }

    // MARK: - One entry's match

    private struct Candidate {
        let facts: Facts?
        let signals: Signals
        let position: Int
    }

    private enum AliasHit: Equatable {
        case none
        case prefix
        case exact
    }

    /// How a past search term relates to the query; `length` is the stored term's.
    private enum TermHit: Equatable {
        case none
        case exact(length: Int)
        case prefix(length: Int)
        case overbounds(length: Int)

        var strength: Int {
            switch self {
            case .none: 0
            case .overbounds: 1
            case .prefix: 2
            case .exact: 3
            }
        }

        var isExact: Bool { if case .exact = self { true } else { false } }
        var isPrefix: Bool { if case .prefix = self { true } else { false } }

        /// A stored term this long or longer is specific enough to reorder a longer query.
        var isLongOverbounds: Bool {
            if case .overbounds(let length) = self { length >= LauncherOrder.overboundsFloor } else { false }
        }
    }

    /// Nil when the entry does not match at all.
    private struct Facts {
        let alias: AliasHit
        let isBoosted: Bool
        let titleExact: Bool
        /// The best of the title and alternate titles; an exact hit is `Int.max`.
        let title: Int
        let titlePrefix: Bool
        let subtitleExact: Bool
        let subtitle: Int
        let term: TermHit

        init?(profile: SearchProfile, signals: Signals, query: Query, sensitivity: SearchSensitivity) {
            let latinLength = query.latin.units.count
            let typedLength = query.typed.units.count
            alias = signals.alias.map { Self.aliasHit($0, query.typed) } ?? .none
            isBoosted = signals.boostedTerms.contains(query.term)
            let titleMatch = LauncherMatch.match(query.latin, in: profile.title)
            var alternateTitles = profile.alternateTitles
            if alias == .none, let text = signals.alias { alternateTitles.append(text) }
            let alternates = alternateTitles.map { LauncherMatch.match(query.typed, in: $0) }
            let subtitleMatch = profile.subtitle.flatMap { LauncherMatch.match(query.latin, in: $0) }

            func passes(_ outcome: LauncherMatch.Outcome?, _ length: Int) -> Bool {
                outcome.map { sensitivity.accepts($0, queryLength: length) } ?? false
            }
            let isMatching =
                alias != .none || passes(titleMatch, latinLength)
                || alternates.contains { passes($0, typedLength) } || passes(subtitleMatch, latinLength)
                || profile.keywords.contains {
                    passes(LauncherMatch.match(query.latin, in: $0), latinLength)
                }
            guard isMatching else { return nil }

            titleExact = titleMatch == .exact || alternates.contains { $0 == .exact }
            title = alternates.reduce(Self.value(titleMatch)) { max($0, Self.value($1)) }
            titlePrefix =
                profile.title.units.starts(with: query.latin.units)
                || alternateTitles.contains { $0.units.starts(with: query.typed.units) }
            subtitleExact = subtitleMatch == .exact
            subtitle = Self.value(subtitleMatch)
            term = Self.termHit(signals.usage.searchTerms, query.latin.units)
        }

        /// A miss sorts below every alignment.
        private static func value(_ outcome: LauncherMatch.Outcome?) -> Int {
            outcome?.value ?? .min
        }

        /// A prefix hit must leave some of the alias still untyped.
        private static func aliasHit(_ alias: SearchText, _ query: SearchText) -> AliasHit {
            let a = alias.units
            let q = query.units
            if a.count > q.count { return a.starts(with: q) ? .prefix : .none }
            return a == q ? .exact : .none
        }

        /// Newest term first: an exact one wins outright, then the newest prefix.
        private static func termHit(_ terms: [String], _ query: [UInt16]) -> TermHit {
            var best = TermHit.none
            for term in terms.reversed() {
                let stored = Array(term.utf16)
                guard !stored.isEmpty else { continue }
                if stored.count > query.count {
                    guard stored.starts(with: query) else { continue }
                    if !best.isPrefix { best = .prefix(length: stored.count) }
                } else if stored.count == query.count {
                    if stored == query { return .exact(length: stored.count) }
                } else if query.starts(with: stored) {
                    let extra = query.count - stored.count
                    guard extra <= LauncherOrder.overboundsReach else { continue }
                    switch best {
                    case .none: best = .overbounds(length: stored.count)
                    case .overbounds(let length) where stored.count > length:
                        best = .overbounds(length: stored.count)
                    default: break
                    }
                }
            }
            return best
        }
    }

    /// How many characters a query may run past a stored term and still be read as it.
    private static let overboundsReach = 3
    private static let overboundsFloor = 3

    // MARK: - The comparator

    private static func orders(_ a: Candidate, before b: Candidate, length: Int) -> Bool {
        let order = compare(a, b, length: length)
        return order != 0 ? order < 0 : a.position < b.position
    }

    /// Negative puts `a` first; the first rule that separates the two decides.
    private static func compare(_ a: Candidate, _ b: Candidate, length: Int) -> Int {
        guard let x = a.facts, let y = b.facts else { return tiebreak(a, b) }
        if x.alias != y.alias, x.alias == .exact || y.alias == .exact {
            return x.alias == .exact ? -1 : 1
        }
        if x.isBoosted != y.isBoosted {
            let (boosted, other) = x.isBoosted ? (a, b) : (b, a)
            let used = other.signals.usage.frecency
            if !(used > 1 && used > boosted.signals.usage.frecency) { return x.isBoosted ? -1 : 1 }
        }
        if length > 3, x.titleExact || y.titleExact {
            guard x.titleExact, y.titleExact else { return x.titleExact ? -1 : 1 }
            return first(termStrength(x.term, y.term), frecency(a, b)) ?? tiebreak(a, b)
        }
        if x.term.isExact || y.term.isExact {
            guard x.term.isExact, y.term.isExact else { return x.term.isExact ? -1 : 1 }
            return first(frecency(a, b)) ?? tiebreak(a, b)
        }
        if x.subtitleExact || y.subtitleExact {
            guard x.subtitleExact, y.subtitleExact else { return x.subtitleExact ? -1 : 1 }
            return first(frecency(a, b), descending(x.title, y.title)) ?? tiebreak(a, b)
        }
        if (x.alias == .prefix) != (y.alias == .prefix) { return x.alias == .prefix ? -1 : 1 }
        if x.term.isPrefix != y.term.isPrefix { return x.term.isPrefix ? -1 : 1 }
        if x.term != .none, y.term != .none {
            if x.term.isPrefix, y.term.isPrefix, let order = first(frecency(a, b)) { return order }
            if case .overbounds(let left) = x.term, case .overbounds(let right) = y.term, left != right,
                left >= overboundsFloor || right >= overboundsFloor
            {
                return descending(left, right)
            }
            if x.term.isLongOverbounds != y.term.isLongOverbounds { return x.term.isLongOverbounds ? -1 : 1 }
        }
        if x.term.isLongOverbounds, y.term == .none { return -1 }
        if y.term.isLongOverbounds, x.term == .none { return 1 }
        let order = first(
            descending(max(x.title, x.subtitle), max(y.title, y.subtitle)), frecency(a, b),
            descending(x.title, y.title), descending(x.titlePrefix, y.titlePrefix),
            descending(a.signals.priority, b.signals.priority))
        return order ?? collate(a, b)
    }

    /// What decides two entries the query cannot tell apart.
    private static func tiebreak(_ a: Candidate, _ b: Candidate) -> Int {
        let aliased = descending(a.signals.alias != nil, b.signals.alias != nil)
        return first(frecency(a, b), aliased, descending(a.signals.priority, b.signals.priority))
            ?? collate(a, b)
    }

    private static func termStrength(_ x: TermHit, _ y: TermHit) -> Int {
        if x.strength != y.strength { return descending(x.strength, y.strength) }
        if case .overbounds(let left) = x, case .overbounds(let right) = y { return descending(left, right) }
        return 0
    }

    private static func frecency(_ a: Candidate, _ b: Candidate) -> Int {
        descending(a.signals.usage.frecency, b.signals.usage.frecency)
    }

    /// Numeric and case-blind: `Item 2` before `Item 10`.
    private static func collate(_ a: Candidate, _ b: Candidate) -> Int {
        switch a.signals.title.localizedStandardCompare(b.signals.title) {
        case .orderedAscending: -1
        case .orderedDescending: 1
        case .orderedSame: 0
        }
    }

    private static func descending<Value: Comparable>(_ left: Value, _ right: Value) -> Int {
        left == right ? 0 : (left > right ? -1 : 1)
    }

    private static func descending(_ left: Bool, _ right: Bool) -> Int {
        left == right ? 0 : (left ? -1 : 1)
    }

    private static func first(_ orders: Int...) -> Int? {
        orders.first { $0 != 0 }
    }
}
