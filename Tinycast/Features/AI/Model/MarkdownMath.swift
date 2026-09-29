import Foundation

/// Finds the math in one span of inline Markdown, before Foundation's parse eats its backslashes.
enum MarkdownMath {
    enum Piece: Equatable {
        case text(String)
        case math(tex: String, display: Bool, source: String)
        /// An opener with no closer yet — a stream mid-equation — shown as written.
        case unclosed(String)
    }

    /// `\(…\)` and `$…$` inline, `\[…\]` and `$$…$$` display; code spans and `\$` stay text.
    static func pieces(of text: String) -> [Piece] {
        let characters = Array(text)
        var pieces: [Piece] = []
        var plain = ""
        var index = 0
        func flush() {
            if !plain.isEmpty { pieces.append(.text(plain)) }
            plain = ""
        }
        while index < characters.count {
            let character = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            if character == "`" {
                let end = codeSpanEnd(from: index, in: characters)
                plain += String(characters[index..<end])
                index = end
                continue
            }
            let opener: (length: Int, closer: [Character], display: Bool)? =
                switch (character, next) {
                case ("\\", "("): (2, ["\\", ")"], false)
                case ("\\", "["): (2, ["\\", "]"], true)
                case ("$", "$"): (2, ["$", "$"], true)
                case ("$", _): (1, ["$"], false)
                default: nil
                }
            guard let opener else {
                // An escape pair is text as a whole, so `\$` never opens and `\\(` is no `\(`.
                let length = character == "\\" && next != nil ? 2 : 1
                plain += String(characters[index..<index + length])
                index += length
                continue
            }
            let bodyStart = index + opener.length
            guard let close = closer(opener.closer, from: bodyStart, in: characters) else {
                if opener.closer == ["$"] {
                    plain.append(character)
                    index += 1
                    continue
                }
                flush()
                pieces.append(.unclosed(String(characters[index...])))
                return pieces
            }
            let tex = String(characters[bodyStart..<close])
            let end = close + opener.closer.count
            if opener.closer == ["$"], !isInlineDollar(tex, followedBy: end, in: characters) {
                plain.append(character)
                index += 1
                continue
            }
            guard !tex.allSatisfy(\.isWhitespace) else {
                plain += String(characters[index..<end])
                index = end
                continue
            }
            flush()
            pieces.append(
                .math(tex: tex, display: opener.display, source: String(characters[index..<end])))
            index = end
        }
        flush()
        return pieces
    }

    /// Drops an equation still arriving at the text's end; a lone `$` may be a price, so it stays.
    static func holdingBackUnclosed(_ text: String) -> String {
        guard case .unclosed(let tail)? = pieces(of: text).last, text.hasSuffix(tail) else { return text }
        return String(text.dropLast(tail.count))
    }

    /// Pandoc's rule, which keeps "$5 and $10" prose: `$x$` hugs its content, no digit after.
    private static func isInlineDollar(
        _ tex: String, followedBy end: Int, in characters: [Character]
    )
        -> Bool
    {
        guard let first = tex.first, let last = tex.last, !first.isWhitespace, !last.isWhitespace
        else { return false }
        return end >= characters.count || !characters[end].isNumber
    }

    /// The first unescaped closer, short of any code span: a lone `$` pairs with the very next one.
    private static func closer(
        _ closer: [Character], from start: Int, in characters: [Character]
    )
        -> Int?
    {
        var index = start
        while index + closer.count <= characters.count, characters[index] != "`" {
            if Array(characters[index..<index + closer.count]) == closer { return index }
            index += characters[index] == "\\" ? 2 : 1
        }
        return nil
    }

    /// Past a code span's closing run of equal length, or past the opening run if none closes it.
    private static func codeSpanEnd(from start: Int, in characters: [Character]) -> Int {
        let run = characters[start...].prefix(while: { $0 == "`" }).count
        var index = start + run
        while index < characters.count {
            let length = characters[index...].prefix(while: { $0 == "`" }).count
            if length == run { return index + length }
            index += max(length, 1)
        }
        return start + run
    }
}
