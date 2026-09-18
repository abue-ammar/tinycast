import Foundation

/// Word-level diff, so a rewrite shows what it changed rather than asking the reader to spot it.
enum TextDiffEngine: Sendable {
    enum Chunk: Equatable, Sendable {
        case equal(String)
        case inserted(String)
        case deleted(String)
    }

    /// The traceback is quadratic, so an unbounded diff still asks for gigabytes — a bit a cell.
    static let maxTokens = 4_000

    static func diff(original: String, modified: String) -> [Chunk] {
        if original == modified { return original.isEmpty ? [] : [.equal(original)] }
        if original.isEmpty { return [.inserted(modified)] }
        if modified.isEmpty { return [.deleted(original)] }

        let old = tokenize(original)
        let new = tokenize(modified)
        guard old.count <= maxTokens, new.count <= maxTokens else {
            return [.deleted(original), .inserted(modified)]
        }

        let traceback = longestCommonSubsequence(old, new)
        var reversed: [Chunk] = []
        var i = old.count
        var j = new.count
        while i > 0 || j > 0 {
            if i > 0, j > 0, old[i - 1] == new[j - 1] {
                reversed.append(.equal(old[i - 1]))
                i -= 1
                j -= 1
            } else if j > 0, i == 0 || traceback.preferInsert(row: i, col: j) {
                reversed.append(.inserted(new[j - 1]))
                j -= 1
            } else {
                reversed.append(.deleted(old[i - 1]))
                i -= 1
            }
        }
        return coalesce(reversed.reversed())
    }

    /// Words and the runs between them, so a change lands on a boundary rather than mid-letter.
    private static func tokenize(_ string: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inWord = false
        for character in string {
            let isWordCharacter = character.isLetter || character.isNumber
            if isWordCharacter == inWord, !current.isEmpty {
                current.append(character)
            } else {
                if !current.isEmpty { tokens.append(current) }
                current = String(character)
                inWord = isWordCharacter
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// One row of scores plus a traceback bit per cell, so the cap costs 1 bit rather than 16.
    private static func longestCommonSubsequence(_ old: [String], _ new: [String]) -> Traceback {
        var traceback = Traceback(rows: old.count + 1, cols: new.count + 1)
        var previous = [UInt16](repeating: 0, count: new.count + 1)
        var current = [UInt16](repeating: 0, count: new.count + 1)
        for i in 0..<old.count {
            current[0] = 0
            for j in 0..<new.count {
                if old[i] == new[j] {
                    current[j + 1] = previous[j] + 1
                } else {
                    let fromLeft = current[j]
                    let fromUp = previous[j + 1]
                    current[j + 1] = max(fromLeft, fromUp)
                    if fromLeft >= fromUp {
                        traceback.markPreferInsert(row: i + 1, col: j + 1)
                    }
                }
            }
            swap(&previous, &current)
        }
        return traceback
    }

    /// A bit per cell for "insert over delete" on a tie; a match is read straight off the tokens.
    private struct Traceback {
        private var words: [UInt64]
        private let cols: Int

        init(rows: Int, cols: Int) {
            self.cols = cols
            words = [UInt64](repeating: 0, count: (rows * cols + 63) / 64)
        }

        mutating func markPreferInsert(row: Int, col: Int) {
            let bit = row * cols + col
            words[bit / 64] |= (1 as UInt64) << UInt64(bit % 64)
        }

        func preferInsert(row: Int, col: Int) -> Bool {
            let bit = row * cols + col
            return words[bit / 64] & ((1 as UInt64) << UInt64(bit % 64)) != 0
        }
    }

    /// Adjacent chunks of one kind become one, so the reader sees a changed phrase, not five words.
    private static func coalesce(_ chunks: [Chunk]) -> [Chunk] {
        chunks.reduce(into: []) { result, chunk in
            switch (result.last, chunk) {
            case (.equal(let a), .equal(let b)): result[result.count - 1] = .equal(a + b)
            case (.inserted(let a), .inserted(let b)): result[result.count - 1] = .inserted(a + b)
            case (.deleted(let a), .deleted(let b)): result[result.count - 1] = .deleted(a + b)
            default: result.append(chunk)
            }
        }
    }
}
