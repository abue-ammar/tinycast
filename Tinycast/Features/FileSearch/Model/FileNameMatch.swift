import Foundation

/// Byte-level filename scoring: fzf-v1 placement, word bonuses and one forgiven typo.
enum FileNameMatch {
    typealias Bytes = UnsafeBufferPointer<UInt8>

    enum Mode: Sendable, Equatable {
        case fuzzy
        case exact
        case prefix
        case suffix
    }

    struct Token: Sendable, Equatable {
        let text: [UInt8]
        let mode: Mode
        let negate: Bool
        let mask: UInt64
        /// Classes a typo may leave out of a name: every class but the first letter's.
        let loose: UInt64
        /// `startBit` of the first letter, or 0 when the token takes no typos.
        let start: UInt64

        init(text: [UInt8], mode: Mode, negate: Bool) {
            self.text = text
            self.mode = mode
            self.negate = negate
            mask = FileNameMatch.charMask(text)
            if FileNameMatch.takesTypos(text, mode: mode) {
                loose = mask & ~FileNameMatch.charBit(text[0])
                start = FileNameMatch.startBit(text[0])
            } else {
                loose = 0
                start = 0
            }
        }

        var takesTypos: Bool { start != 0 }

        /// Branchless, so the sweep over every distinct name stays a straight line of ANDs.
        @inline(__always)
        func fits(_ nameMask: UInt64) -> Bool {
            let miss = mask & ~nameMask
            let oneLooseClass = (miss & ~loose) | (miss & (miss &- 1)) == 0
            return miss == 0 || (oneLooseClass && nameMask & start != 0)
        }
    }

    static let typoMinimumLength = 5
    static let typoCost = 60
    private static let scoreMatch = 16
    private static let gapStart = -3
    private static let gapExtension = -1
    private static let bonusBoundary = 8
    private static let bonusCamel = 7
    private static let bonusConsecutive = 4

    /// Typos are byte edits, so a multibyte character would be split by one; ASCII words only.
    static func takesTypos(_ text: [UInt8], mode: Mode) -> Bool {
        mode == .fuzzy && text.count >= typoMinimumLength && text.allSatisfy { $0 < 0x80 }
    }

    // MARK: Masks

    @inline(__always)
    static func charBit(_ byte: UInt8) -> UInt64 {
        switch byte {
        case 0x61...0x7A: return 1 << UInt64(byte - 0x61)
        case 0x41...0x5A: return 1 << UInt64(byte - 0x41)
        case 0x30...0x39: return 1 << UInt64(26 + byte - 0x30)
        case 0x2E: return 1 << 36
        case 0x2D, 0x5F: return 1 << 37
        case 0x20: return 1 << 38
        case 0x80...: return 1 << 39
        default: return 1 << 40
        }
    }

    /// Bits 41–63 hash where a word may start, which is where a typo match has to begin.
    @inline(__always)
    static func startBit(_ byte: UInt8) -> UInt64 {
        1 << UInt64(41 + fold(byte) % 23)
    }

    static func charMask<S: Sequence<UInt8>>(_ bytes: S) -> UInt64 {
        bytes.reduce(0) { $0 | charBit($1) }
    }

    static func nameMask(_ name: Bytes) -> UInt64 {
        var mask = charMask(name)
        let offset = leadingDotOffset(name)
        if offset < name.count { mask |= startBit(name[offset]) }
        var index = 1
        while index < name.count {
            if name[index - 1] == 0x20 { mask |= startBit(name[index]) }
            index += 1
        }
        return mask
    }

    // MARK: Scoring

    @inline(__always)
    static func fold(_ byte: UInt8) -> UInt8 {
        byte &- 0x41 < 26 ? byte | 0x20 : byte
    }

    /// The token's score against one name, or nil when it does not match. `nameMask` may over-claim.
    static func score(_ name: Bytes, nameMask: UInt64, token: Token, text: Bytes) -> Int? {
        let count = name.count
        switch token.mode {
        case .fuzzy where token.takesTypos:
            let clean = token.mask & ~nameMask == 0 ? fuzzyScore(name, text, cap: 100) : nil
            let typo = nameMask & token.start != 0 ? typoScore(name, nameMask, text) : nil
            return maximum(clean, typo)
        case .fuzzy:
            return fuzzyScore(name, text, cap: 100)
        case .exact:
            guard let position = find(text, in: name) else { return nil }
            return 40 + (position == 0 ? 30 : 0) - lengthPenalty(count)
        case .prefix:
            guard count >= text.count, hasFolded(name, prefix: text, at: 0) else { return nil }
            return 60 - lengthPenalty(count)
        case .suffix:
            guard count >= text.count, hasFolded(name, prefix: text, at: count - text.count)
            else { return nil }
            return 50 - lengthPenalty(count)
        }
    }

    /// Whether the token hits at all; a fuzzy one only needs its letters in order.
    static func matches(_ name: Bytes, token: Token, text: Bytes) -> Bool {
        guard token.mode == .fuzzy else {
            return score(name, nameMask: ~0, token: token, text: text) != nil
        }
        var next = 0
        for byte in name where fold(byte) == text[next] {
            next += 1
            if next == text.count { return true }
        }
        return false
    }

    /// Leftmost-ending match, shrunk from the right, then scored with the boundary bonuses.
    static func fuzzyScore(_ name: Bytes, _ query: Bytes, cap: Int) -> Int? {
        guard !query.isEmpty else { return nil }
        var end = 0
        var from = 0
        for byte in query {
            guard let found = firstFolded(byte, in: name, from: from, through: name.count - 1)
            else { return nil }
            end = found
            from = found + 1
        }
        if query.count == 1 { return singleScore(name, at: end, cap: cap) }

        var start = end + 1
        for byte in query.reversed() {
            guard let found = lastFolded(byte, in: name, before: start) else { return nil }
            start = found
        }

        var score = 0
        var at = start
        var firstBonus = 0
        for (position, byte) in query.enumerated() {
            var isRun = false
            if position > 0 {
                let last = at
                guard let found = firstFolded(byte, in: name, from: last + 1, through: end)
                else { return nil }
                at = found
                isRun = at == last + 1
                if !isRun { score += gapStart + (at - last - 2) * gapExtension }
            }
            let previous = at == 0 ? CharClass.delimiter : CharClass(name[at - 1])
            var bonus = bonus(previous, CharClass(name[at]))
            if isRun {
                if bonus >= bonusBoundary && bonus > firstBonus { firstBonus = bonus }
                bonus = max(bonus, firstBonus, bonusConsecutive)
            } else {
                firstBonus = bonus
            }
            score += scoreMatch + (position == 0 ? bonus * 2 : bonus)
        }

        let offset = leadingDotOffset(name)
        let stem = stemEnd(name, offset: offset)
        let contiguous = end + 1 - start == query.count
        let placed: Int
        if start == offset && contiguous && end + 1 == name.count {
            placed = 100
        } else if start == offset && contiguous && end + 1 == stem {
            placed = 80
        } else if start == offset && contiguous {
            placed = 30
        } else {
            placed = 0
        }
        return score + min(placed, cap) - lengthPenalty(name.count)
    }

    private static func singleScore(_ name: Bytes, at index: Int, cap: Int) -> Int {
        let previous = index == 0 ? CharClass.delimiter : CharClass(name[index - 1])
        var score = scoreMatch + bonus(previous, CharClass(name[index])) * 2
        let offset = leadingDotOffset(name)
        if index == offset {
            let placed: Int
            if index + 1 == name.count {
                placed = 100
            } else if index + 1 == stemEnd(name, offset: offset) {
                placed = 80
            } else {
                placed = 30
            }
            score += min(cap, placed)
        }
        return score - lengthPenalty(name.count)
    }

    /// Only word starts after a space are tried: other boundaries cost a scan of every name.
    private static func typoScore(_ name: Bytes, _ nameMask: UInt64, _ query: Bytes) -> Int? {
        var best = typoScore(name, from: leadingDotOffset(name), query)
        guard nameMask & charBit(0x20) != 0 else { return best }
        for index in 0..<name.count where name[index] == 0x20 {
            best = maximum(best, typoScore(name, from: index + 1, query))
        }
        return best
    }

    /// Scored as if the right letters were typed, and never placed above a clean prefix.
    private static func typoScore(_ name: Bytes, from start: Int, _ query: Bytes) -> Int? {
        guard start < name.count, fold(name[start]) == query[0] else { return nil }
        let word = Bytes(rebasing: name[start...])
        guard let length = oneEditPrefix(word, query), length <= 128 else { return nil }
        let corrected = (0..<length).map { fold(word[$0]) }
        return corrected.withUnsafeBufferPointer { fuzzyScore(name, $0, cap: 30) }
            .map { $0 - typoCost }
    }

    /// How long a prefix of `word` the query spells with exactly one edit. Digits are never edited.
    static func oneEditPrefix(_ word: Bytes, _ query: Bytes) -> Int? {
        guard
            let index = (0..<query.count).first(where: {
                $0 >= word.count || fold(word[$0]) != query[$0]
            })
        else { return nil }
        if isDigit(query[index]) || (index < word.count && isDigit(word[index])) { return nil }

        if index + 1 < query.count, index + 1 < word.count, fold(word[index]) == query[index + 1],
            fold(word[index + 1]) == query[index],
            startsFolded(word, at: index + 2, with: query, from: index + 2)
        {
            return query.count
        }
        if index < word.count, startsFolded(word, at: index + 1, with: query, from: index + 1) {
            return query.count
        }
        if startsFolded(word, at: index, with: query, from: index + 1) { return query.count - 1 }
        if index < word.count, startsFolded(word, at: index + 1, with: query, from: index) {
            return query.count + 1
        }
        return nil
    }

    // MARK: Helpers

    private enum CharClass: Equatable {
        case lower
        case upper
        case digit
        case delimiter
        case other

        @inline(__always)
        init(_ byte: UInt8) {
            switch byte {
            case 0x61...0x7A: self = .lower
            case 0x41...0x5A: self = .upper
            case 0x30...0x39: self = .digit
            case 0x20, 0x5F, 0x2D, 0x2E, 0x2F, 0x28, 0x29, 0x5B, 0x5D, 0x2C, 0x2B, 0x40:
                self = .delimiter
            default: self = .other
            }
        }
    }

    @inline(__always)
    private static func bonus(_ previous: CharClass, _ current: CharClass) -> Int {
        switch (previous, current) {
        case (.delimiter, let current) where current != .delimiter: return bonusBoundary
        case (.lower, .upper), (.lower, .digit), (.upper, .digit): return bonusCamel
        default: return 0
        }
    }

    @inline(__always)
    private static func lengthPenalty(_ count: Int) -> Int { min(count, 80) / 3 }

    /// "zshrc" means `.zshrc`, so a leading dot is not where a name starts.
    @inline(__always)
    private static func leadingDotOffset(_ name: Bytes) -> Int {
        name.count > 1 && name[0] == 0x2E ? 1 : 0
    }

    private static func stemEnd(_ name: Bytes, offset: Int) -> Int {
        var index = name.count - 1
        while index > offset {
            if name[index] == 0x2E { return index }
            index -= 1
        }
        return name.count
    }

    @inline(__always)
    private static func isDigit(_ byte: UInt8) -> Bool { byte &- 0x30 < 10 }

    @inline(__always)
    private static func firstFolded(
        _ byte: UInt8, in name: Bytes, from start: Int, through end: Int
    ) -> Int? {
        var index = start
        while index <= end {
            if fold(name[index]) == byte { return index }
            index += 1
        }
        return nil
    }

    @inline(__always)
    private static func lastFolded(_ byte: UInt8, in name: Bytes, before end: Int) -> Int? {
        var index = end - 1
        while index >= 0 {
            if fold(name[index]) == byte { return index }
            index -= 1
        }
        return nil
    }

    private static func hasFolded(_ name: Bytes, prefix: Bytes, at start: Int) -> Bool {
        for offset in 0..<prefix.count where fold(name[start + offset]) != prefix[offset] {
            return false
        }
        return true
    }

    private static func find(_ needle: Bytes, in name: Bytes) -> Int? {
        guard needle.count <= name.count else { return nil }
        for start in 0...(name.count - needle.count) where hasFolded(name, prefix: needle, at: start) {
            return start
        }
        return nil
    }

    /// `word[wordStart...]` begins with `query[queryStart...]`, folded.
    private static func startsFolded(
        _ word: Bytes, at wordStart: Int, with query: Bytes, from queryStart: Int
    ) -> Bool {
        let length = query.count - queryStart
        guard length >= 0, word.count - wordStart >= length else { return false }
        for offset in 0..<length where fold(word[wordStart + offset]) != query[queryStart + offset] {
            return false
        }
        return true
    }

    @inline(__always)
    private static func maximum(_ left: Int?, _ right: Int?) -> Int? {
        switch (left, right) {
        case let (left?, right?): return max(left, right)
        case let (left?, nil): return left
        case let (nil, right?): return right
        case (nil, nil): return nil
        }
    }
}
