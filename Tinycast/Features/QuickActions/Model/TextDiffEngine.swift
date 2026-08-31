import Foundation

/// Word-level diff, so a rewrite shows what it changed rather than asking the reader to spot it.
enum TextDiffEngine: Sendable {
    enum Chunk: Equatable, Sendable {
        case equal(String)
        case inserted(String)
        case deleted(String)
    }

    /// The LCS matrix is quadratic, so an unbounded diff of a long selection asks for gigabytes.
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

        let matrix = longestCommonSubsequence(old, new)
        var reversed: [Chunk] = []
        var i = old.count
        var j = new.count
        while i > 0 || j > 0 {
            if i > 0, j > 0, old[i - 1] == new[j - 1] {
                reversed.append(.equal(old[i - 1]))
                i -= 1
                j -= 1
            } else if j > 0, i == 0 || matrix[i][j - 1] >= matrix[i - 1][j] {
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

    private static func longestCommonSubsequence(_ old: [String], _ new: [String]) -> [[Int]] {
        var table = Array(
            repeating: Array(repeating: 0, count: new.count + 1), count: old.count + 1)
        for i in 0..<old.count {
            for j in 0..<new.count {
                table[i + 1][j + 1] =
                    old[i] == new[j]
                    ? table[i][j] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        return table
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
