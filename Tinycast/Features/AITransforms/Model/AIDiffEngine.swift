import Foundation

/// Pure Foundation word-level diffing engine for comparing original input with AI transformation output.
/// Complies with the Model layer rule: zero AppKit/SwiftUI imports so test harnesses compile cleanly.
enum AIDiffEngine: Sendable {
    enum Chunk: Equatable, Sendable {
        case equal(String)
        case inserted(String)
        case deleted(String)
    }

    /// Computes word-level diff chunks between original and modified text.
    static func diff(original: String, modified: String) -> [Chunk] {
        if original.isEmpty {
            return modified.isEmpty ? [] : [.inserted(modified)]
        }
        if modified.isEmpty {
            return [.deleted(original)]
        }
        if original == modified {
            return [.equal(original)]
        }

        let origTokens = tokenize(original)
        let modTokens = tokenize(modified)

        let matrix = computeLCSMatrix(origTokens, modTokens)
        var chunks: [Chunk] = []

        var i = origTokens.count
        var j = modTokens.count

        var reversedChunks: [Chunk] = []

        while i > 0 || j > 0 {
            if i > 0 && j > 0 && origTokens[i - 1] == modTokens[j - 1] {
                reversedChunks.append(.equal(origTokens[i - 1]))
                i -= 1
                j -= 1
            } else if j > 0 && (i == 0 || matrix[i][j - 1] >= matrix[i - 1][j]) {
                reversedChunks.append(.inserted(modTokens[j - 1]))
                j -= 1
            } else if i > 0 && (j == 0 || matrix[i][j - 1] < matrix[i - 1][j]) {
                reversedChunks.append(.deleted(origTokens[i - 1]))
                i -= 1
            }
        }

        chunks = reversedChunks.reversed()
        return coalesce(chunks)
    }

    /// Renders diff chunks into an `AttributedString` with strikethroughs on deletions and highlights on additions.
    /// Renders diff chunks into an `AttributedString` with strikethroughs on deletions and highlights on additions.
    static func renderDiff(original: String, modified: String) -> AttributedString {
        let chunks = diff(original: original, modified: modified)
        var result = AttributedString()

        for (index, chunk) in chunks.enumerated() {
            switch chunk {
            case .equal(let text):
                result.append(AttributedString(text))

            case .deleted(let text):
                var attr = AttributedString(text)
                attr.inlinePresentationIntent = .strikethrough
                result.append(attr)
                if index + 1 < chunks.count {
                    if case .inserted(let nextText) = chunks[index + 1],
                        !text.hasSuffix(" ") && !nextText.hasPrefix(" ")
                    {
                        result.append(AttributedString(" "))
                    }
                }

            case .inserted(let text):
                var attr = AttributedString(text)
                attr.inlinePresentationIntent = .stronglyEmphasized
                result.append(attr)
            }
        }

        return result
    }

    /// Tokenizes string into words, whitespace, and punctuation so diffing highlights changes naturally at word boundaries.
    static func tokenize(_ string: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inWord = false

        for char in string {
            let isWordChar = char.isLetter || char.isNumber
            if isWordChar == inWord {
                current.append(char)
            } else {
                if !current.isEmpty {
                    tokens.append(current)
                }
                current = String(char)
                inWord = isWordChar
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    private static func computeLCSMatrix(_ a: [String], _ b: [String]) -> [[Int]] {
        let n = a.count
        let m = b.count
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)

        for i in 0..<n {
            for j in 0..<m {
                if a[i] == b[j] {
                    dp[i + 1][j + 1] = dp[i][j] + 1
                } else {
                    dp[i + 1][j + 1] = max(dp[i + 1][j], dp[i][j + 1])
                }
            }
        }
        return dp
    }

    private static func coalesce(_ chunks: [Chunk]) -> [Chunk] {
        var result: [Chunk] = []
        for chunk in chunks {
            if let last = result.last {
                switch (last, chunk) {
                case (.equal(let a), .equal(let b)):
                    result.removeLast()
                    result.append(.equal(a + b))
                case (.inserted(let a), .inserted(let b)):
                    result.removeLast()
                    result.append(.inserted(a + b))
                case (.deleted(let a), .deleted(let b)):
                    result.removeLast()
                    result.append(.deleted(a + b))
                default:
                    result.append(chunk)
                }
            } else {
                result.append(chunk)
            }
        }
        return result
    }
}
