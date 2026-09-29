import Foundation

/// One equation a reply wrote, kept with its source so copying and a fallback give that back.
struct MathFormula: Hashable, Sendable {
    /// As written, delimiters included.
    let source: String
    let root: MathNode
    let display: Bool

    init?(tex: String, source: String, display: Bool) {
        guard let root = MathNode.parse(tex) else { return nil }
        self.source = source
        self.root = root
        self.display = display
    }

    /// Rides the one character an inline formula stands on in `MarkdownBlock.inline`'s result.
    enum Attribute: AttributedStringKey {
        typealias Value = MathFormula
        static let name = "TinycastMathFormula"
    }

    /// What an inline formula occupies in the drawn text, and so in what find searches.
    static let placeholder: Character = "\u{FFFC}"
}
