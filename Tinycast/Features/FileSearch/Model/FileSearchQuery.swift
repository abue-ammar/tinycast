import Foundation

enum FileSearchQuery {
    static let resultLimit = 200
    /// A blank screen is a shortlist, not a browser: enough rows to reach, never to scroll far.
    static let recentLimit = 20
    static let launcherLimit = 5
    /// Category search's threshold too: below it a query matches too many names to be useful.
    static let launcherMinimumLength = 3
    static let priorWeight = 1_500
    static let nonASCIIBit: UInt64 = 1 << 40

    struct Prepared: Sendable {
        let terms: [[UInt8]]
        let whole: [UInt8]
        let mask: UInt64
        let termMasks: [UInt64]

        /// Each term owns one bit of a `UInt8`, so folders can stand in for at most eight.
        var reachesFolders: Bool { (2...8).contains(terms.count) }

        var everyTerm: UInt8 { UInt8(truncatingIfNeeded: (1 << terms.count) - 1) }
    }

    struct TermHits: Sendable {
        var held: UInt8 = 0
        var startingWords: UInt8 = 0
    }

    static func answersLauncher(_ query: String) -> Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).count >= launcherMinimumLength
    }

    static func launcherResults(
        _ query: String, favorites: [FileSearchResult], indexed: [FileSearchResult]
    ) -> [FileSearchResult] {
        guard let prepared = prepare(query) else { return [] }
        let favorites = favorites.filter { file in
            var name = fold(file.name)
            return name.withUTF8 { name in
                prepared.terms.allSatisfy { find($0, in: name) != nil }
            }
        }
        let favoriteIDs = Set(favorites.map(\.id))
        let results = answersLauncher(query) ? indexed.filter { !favoriteIDs.contains($0.id) } : []
        return Array((favorites + results).prefix(launcherLimit))
    }

    static func terms(in query: String) -> [String] {
        query.split(whereSeparator: \Character.isWhitespace).map(String.init)
    }

    static func prepare(_ query: String) -> Prepared? {
        let terms = terms(in: query).map { Array(fold($0).utf8) }
        guard !terms.isEmpty else { return nil }
        let whole = Array(terms.joined(separator: [0x20]))
        // From the terms, not `whole`: its spaces are no letter a name has to contain.
        return Prepared(
            terms: terms, whole: whole, mask: mask(of: terms.joined()), termMasks: terms.map { mask(of: $0) })
    }

    static func fold(_ text: String) -> String {
        guard text.utf8.contains(where: { $0 >= 0x80 }) else { return text.lowercased() }
        return text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// A name's mask covers its folded spelling too, so `resume` still passes for `Résumé`.
    static func nameMask(_ name: UnsafeBufferPointer<UInt8>) -> UInt64 {
        let raw = mask(of: name)
        guard raw & nonASCIIBit != 0 else { return raw }
        return raw | mask(of: fold(String(decoding: name, as: UTF8.self)).utf8)
    }

    static func mask<Bytes: Sequence<UInt8>>(of bytes: Bytes) -> UInt64 {
        var mask: UInt64 = 0
        for byte in bytes { mask |= bit(byte) }
        return mask
    }

    @inline(__always)
    private static func bit(_ byte: UInt8) -> UInt64 {
        switch byte {
        case 0x61...0x7A: return 1 << UInt64(byte - 0x61)
        case 0x41...0x5A: return 1 << UInt64(byte - 0x41)
        case 0x30...0x39: return 1 << UInt64(26 + byte - 0x30)
        case 0x2E: return 1 << 36
        case 0x5F: return 1 << 37
        case 0x2D: return 1 << 38
        case 0x20: return 1 << 39
        case 0x80...: return nonASCIIBit
        default: return 0
        }
    }

    static func score(
        _ query: Prepared, name: UnsafeBufferPointer<UInt8>, mask: UInt64, prior: Int8
    ) -> Int? {
        guard mask & nonASCIIBit != 0 else { return score(query, folded: name, prior: prior) }
        let folded = Array(fold(String(decoding: name, as: UTF8.self)).utf8)
        return folded.withUnsafeBufferPointer { score(query, folded: $0, prior: prior) }
    }

    private static func score(
        _ query: Prepared, folded name: UnsafeBufferPointer<UInt8>, prior: Int8
    ) -> Int? {
        var first = 0
        for (index, term) in query.terms.enumerated() {
            guard let at = find(term, in: name) else { return nil }
            if index == 0 { first = at }
        }
        let wholeAt = query.terms.count == 1 ? first : find(query.whole, in: name)
        var score =
            Int(prior) * priorWeight - 4 * name.count + leadScore(query.terms[0], at: first, in: name)
        if wholeAt == 0, name.count == query.whole.count {
            score += 4_000
        } else if query.terms.count > 1, wholeAt != nil {
            score += 1_500
        }
        return score
    }

    static func score(
        _ query: Prepared, name: UnsafeBufferPointer<UInt8>, mask: UInt64, holding held: UInt8,
        prior: Int8
    ) -> Int? {
        withFolded(name, mask: mask) { name in
            let lead = query.terms[held.trailingZeroBitCount]
            guard let first = find(lead, in: name) else { return nil }
            var score = Int(prior) * priorWeight - 4 * name.count + leadScore(lead, at: first, in: name)
            if first == 0, name.count == lead.count { score += 4_000 }
            return score
        }
    }

    static func hits(_ query: Prepared, name: UnsafeBufferPointer<UInt8>, mask: UInt64) -> TermHits {
        var candidates: UInt8 = 0
        for index in query.termMasks.indices where mask & query.termMasks[index] == query.termMasks[index] {
            candidates |= 1 << index
        }
        guard candidates != 0 else { return TermHits() }
        return withFolded(name, mask: mask) { name in
            var hits = TermHits()
            var remaining = candidates
            while remaining != 0 {
                let index = remaining.trailingZeroBitCount
                remaining &= remaining - 1
                let term = query.terms[index]
                guard let first = find(term, in: name) else { continue }
                hits.held |= 1 << index
                if startsWord(term, in: name, from: first) { hits.startingWords |= 1 << index }
            }
            return hits
        }
    }

    private static func withFolded<T>(
        _ name: UnsafeBufferPointer<UInt8>, mask: UInt64, _ body: (UnsafeBufferPointer<UInt8>) -> T
    ) -> T {
        guard mask & nonASCIIBit != 0 else { return body(name) }
        let folded = Array(fold(String(decoding: name, as: UTF8.self)).utf8)
        return folded.withUnsafeBufferPointer(body)
    }

    private static func leadScore(
        _ lead: [UInt8], at first: Int, in name: UnsafeBufferPointer<UInt8>
    ) -> Int {
        var score = first == 0 ? 2_000 : isBoundary(name, at: first) ? 1_000 : 0
        // `report` should find `report.pdf` ahead of `reporting.pdf`.
        let end = first + lead.count
        if end == name.count || !isAlphanumeric(name[end]) { score += 500 }
        return score
    }

    private static func startsWord(
        _ term: [UInt8], in name: UnsafeBufferPointer<UInt8>, from first: Int
    ) -> Bool {
        var at = first
        while at > 0, !isBoundary(name, at: at) {
            guard let next = find(term, in: UnsafeBufferPointer(rebasing: name[(at + 1)...])) else {
                return false
            }
            at += 1 + next
        }
        return true
    }

    static func find(_ needle: [UInt8], in haystack: UnsafeBufferPointer<UInt8>) -> Int? {
        let count = needle.count
        guard count > 0, count <= haystack.count else { return count == 0 ? 0 : nil }
        return needle.withUnsafeBufferPointer { needle in
            let head = needle[0]
            var start = 0
            while start <= haystack.count - count {
                if lower(haystack[start]) == head {
                    var offset = 1
                    while offset < count, lower(haystack[start + offset]) == needle[offset] {
                        offset += 1
                    }
                    if offset == count { return start }
                }
                start += 1
            }
            return nil
        }
    }

    @inline(__always)
    private static func lower(_ byte: UInt8) -> UInt8 {
        byte &- 0x41 < 26 ? byte | 0x20 : byte
    }

    @inline(__always)
    private static func isAlphanumeric(_ byte: UInt8) -> Bool {
        byte &- 0x61 < 26 || byte &- 0x41 < 26 || byte &- 0x30 < 10 || byte >= 0x80
    }

    private static func isBoundary(_ name: UnsafeBufferPointer<UInt8>, at index: Int) -> Bool {
        let previous = name[index - 1]
        guard isAlphanumeric(previous) else { return true }
        return previous &- 0x61 < 26 && name[index] &- 0x41 < 26
    }
}
