import Foundation

/// A formula as TeX reads it: atoms with their spacing kind, and the structures that stack them.
indirect enum MathNode: Hashable, Sendable {
    /// One drawn character, already in its math alphabet.
    case symbol(String, Kind)
    /// Upright words: `\text`, and `\bmod`'s "mod".
    case text(String, Kind)
    case operatorName(String, limits: Bool)
    case largeOperator(String, limits: Bool)
    case row([MathNode])
    case scripts(base: MathNode, superscript: MathNode?, subscript: MathNode?)
    /// `\overset` and `\underset`: a base with a script set squarely above or below it.
    case stack(base: MathNode, over: MathNode?, under: MathNode?)
    case fraction(numerator: MathNode, denominator: MathNode, rule: Bool, style: Style?)
    case radical(MathNode, degree: MathNode?)
    /// `\left…\right`; an empty side is `\left.`.
    case fenced(open: String, body: MathNode, close: String)
    /// `\big(` and its siblings: 1 to 4 steps taller than the text.
    case delimiter(String, size: Int, Kind)
    case accent(MathNode, mark: String, wide: Bool)
    case overline(MathNode)
    case underline(MathNode)
    case boxed(MathNode)
    /// In mu, TeX's eighteenth of an em.
    case space(Double)
    case styled(Style, MathNode)
    case table(Table)

    /// TeX's atom kinds, which decide the space between two neighbours.
    enum Kind: Hashable, Sendable {
        case ord, op, bin, rel, open, close, punct, inner
    }

    enum Style: Hashable, Sendable {
        case display, text, script, scriptScript
    }

    enum Alphabet: Hashable, Sendable {
        case italic, upright, bold, boldItalic, doubleStruck, script, fraktur, sansSerif, monospace
    }

    /// Matrices, cases and aligned equations: cells in rows, columns aligned and spaced by pattern.
    struct Table: Hashable, Sendable {
        enum Alignment: Hashable, Sendable {
            case leading, center, trailing
        }

        let rows: [[MathNode]]
        /// Repeats across the columns, as aligned's right-left pairs do.
        let alignments: [Alignment]
        /// In mu after each column, repeating the same way.
        let gaps: [Double]
        let style: Style
    }

    /// Nil outside the supported subset, so the reply's source shows instead of a guess.
    static func parse(_ tex: String) -> MathNode? {
        guard tex.count <= maximumLength else { return nil }
        var reader = TeXReader(characters: Array(tex))
        return try? reader.formula()
    }

    /// A reply is untrusted text; past these, a formula shows as source rather than typesetting.
    static let maximumLength = 4000
    fileprivate static let maximumDepth = 40
}

private struct TeXReader {
    enum Failure: Error {
        case unsupported
    }

    enum Token: Equatable {
        case command(String)
        case character(Character)
        case open
        case close
        case superscript
        case `subscript`
        case alignment
        case end
    }

    /// Where a list stops: each structure ends on its own token.
    enum Stop: Equatable {
        case end
        case brace
        case bracket
        case right
        case cell
    }

    let characters: [Character]
    var index = 0
    var depth = 0
    var alphabet = MathNode.Alphabet.italic

    init(characters: [Character]) {
        self.characters = characters
    }

    mutating func formula() throws -> MathNode {
        let rows = try cells()
        guard index >= characters.count else { throw Failure.unsupported }
        if rows.count == 1, rows[0].count == 1 { return .row(rows[0][0]) }
        let aligned = rows.contains { $0.count > 1 }
        return .table(
            .init(
                rows: rows.map { $0.map(MathNode.row) },
                alignments: aligned ? [.trailing, .leading] : [.center], gaps: aligned ? [0, 36] : [0],
                style: .display))
    }

    // MARK: Tokens

    mutating func next() -> Token {
        skipSpace()
        guard index < characters.count else { return .end }
        let character = characters[index]
        index += 1
        switch character {
        case "{": return .open
        case "}": return .close
        case "^": return .superscript
        case "_": return .subscript
        case "&": return .alignment
        case "\\": return command()
        default: return .character(character)
        }
    }

    func peek() -> Token {
        var copy = self
        return copy.next()
    }

    private mutating func command() -> Token {
        guard index < characters.count else { return .command("") }
        let letters = characters[index...].prefix(while: { $0.isASCII && $0.isLetter })
        guard letters.isEmpty else {
            index += letters.count
            return .command(String(letters))
        }
        index += 1
        return .command(String(characters[index - 1]))
    }

    /// Math mode ignores spaces, and `%` comments to the end of the line.
    private mutating func skipSpace() {
        while index < characters.count {
            if characters[index].isWhitespace {
                index += 1
            } else if characters[index] == "%" {
                while index < characters.count, !characters[index].isNewline { index += 1 }
            } else {
                return
            }
        }
    }

    // MARK: Lists

    mutating func list(until stop: Stop) throws -> [MathNode] {
        depth += 1
        defer { depth -= 1 }
        guard depth <= MathNode.maximumDepth else { throw Failure.unsupported }
        var nodes: [MathNode] = []
        while true {
            let start = index
            let token = next()
            switch token {
            case .end:
                guard stop == .end || stop == .cell else { throw Failure.unsupported }
                index = start
                return nodes
            case .close:
                guard stop == .brace else { throw Failure.unsupported }
                return nodes
            case .character("]") where stop == .bracket:
                return nodes
            case .alignment, .command("\\"), .command("cr"):
                guard stop == .cell else { throw Failure.unsupported }
                index = start
                return nodes
            case .command("end"):
                guard stop == .cell else { throw Failure.unsupported }
                index = start
                return nodes
            case .command("right"):
                guard stop == .right else { throw Failure.unsupported }
                return nodes
            case .superscript, .subscript:
                try attachScript(token == .superscript, to: &nodes)
            case .character("'"):
                try attachPrimes(to: &nodes)
            case .command("limits"), .command("nolimits"):
                try setLimits(token == .command("limits"), on: &nodes)
            default:
                if case .command(let name) = token, let style = Self.styles[name] {
                    return nodes + [.styled(style, .row(try list(until: stop)))]
                }
                nodes.append(try atom(token))
            }
        }
    }

    private static let styles: [String: MathNode.Style] = [
        "displaystyle": .display, "textstyle": .text, "scriptstyle": .script,
        "scriptscriptstyle": .scriptScript
    ]

    /// Rows of cells up to `\end` or the end of the formula.
    mutating func cells() throws -> [[[MathNode]]] {
        var rows: [[[MathNode]]] = [[]]
        while true {
            rows[rows.count - 1].append(try list(until: .cell))
            switch next() {
            case .alignment: continue
            case .command("\\"), .command("cr"):
                if case .character("[") = peek() { try skipOptional() }
                rows.append([])
            case .end: return trimmingEmptyLastRow(rows)
            case .command("end"):
                index -= "\\end".count
                return trimmingEmptyLastRow(rows)
            default: throw Failure.unsupported
            }
        }
    }

    /// A trailing `\\` before `\end` would otherwise draw an empty last row.
    private func trimmingEmptyLastRow(_ rows: [[[MathNode]]]) -> [[[MathNode]]] {
        guard rows.count > 1, let last = rows.last, last.allSatisfy(\.isEmpty) else { return rows }
        return Array(rows.dropLast())
    }

    // MARK: Scripts

    private mutating func attachScript(_ isSuperscript: Bool, to nodes: inout [MathNode]) throws {
        let script = try argument()
        let base = nodes.popLast() ?? .row([])
        guard case .scripts(let inner, let superscript, let `subscript`) = base else {
            nodes.append(
                isSuperscript
                    ? .scripts(base: base, superscript: script, subscript: nil)
                    : .scripts(base: base, superscript: nil, subscript: script))
            return
        }
        if isSuperscript {
            guard superscript == nil else { throw Failure.unsupported }
            nodes.append(.scripts(base: inner, superscript: script, subscript: `subscript`))
        } else {
            guard `subscript` == nil else { throw Failure.unsupported }
            nodes.append(.scripts(base: inner, superscript: superscript, subscript: script))
        }
    }

    /// `f''` is `f^{\prime\prime}`, and a `^` straight after joins the same superscript.
    private mutating func attachPrimes(to nodes: inout [MathNode]) throws {
        var primes: [MathNode] = [.symbol("′", .ord)]
        while index < characters.count, characters[index] == "'" {
            index += 1
            primes.append(.symbol("′", .ord))
        }
        if peek() == .superscript {
            _ = next()
            primes.append(try argument())
        }
        let base = nodes.popLast() ?? .row([])
        var `subscript`: MathNode?
        var inner = base
        if case .scripts(let scripted, .none, let existing) = base {
            inner = scripted
            `subscript` = existing
        }
        nodes.append(.scripts(base: inner, superscript: .row(primes), subscript: `subscript`))
    }

    private func setLimits(_ limits: Bool, on nodes: inout [MathNode]) throws {
        switch nodes.popLast() {
        case .largeOperator(let character, _): nodes.append(.largeOperator(character, limits: limits))
        case .operatorName(let text, _): nodes.append(.operatorName(text, limits: limits))
        default: throw Failure.unsupported
        }
    }

    // MARK: Atoms

    /// One script, fraction part or command argument: a braced group or a single atom.
    mutating func argument() throws -> MathNode {
        let token = next()
        switch token {
        case .open: return .row(try list(until: .brace))
        case .end, .close, .alignment, .superscript, .subscript: throw Failure.unsupported
        default: return try atom(token)
        }
    }

    private mutating func atom(_ token: Token) throws -> MathNode {
        switch token {
        case .open: return .row(try list(until: .brace))
        case .character(let character): return try typed(character)
        case .command(let name): return try command(name)
        default: throw Failure.unsupported
        }
    }

    private func typed(_ character: Character) throws -> MathNode {
        if character == "~" { return .space(6) }
        if "#$^_&".contains(character) { throw Failure.unsupported }
        if character.isASCII, character.isLetter || character.isNumber {
            let styled = MathSymbolCatalog.styled(character, in: alphabet)
            return .symbol(styled, .ord)
        }
        return .symbol(MathSymbolCatalog.drawn(character), MathSymbolCatalog.kind(of: character))
    }

    private mutating func command(_ name: String) throws -> MathNode {
        if let symbol = MathSymbolCatalog.symbol(named: name) {
            let character = symbol.character
            let isGreek = character.unicodeScalars.first.map { (0x3B1...0x3F5).contains($0.value) }
            let drawn =
                isGreek == true && character.count == 1
                ? MathSymbolCatalog.styled(Character(character), in: alphabet) : character
            return .symbol(drawn, symbol.kind)
        }
        if let operation = MathSymbolCatalog.largeOperators[name] {
            return .largeOperator(operation.character, limits: operation.limits)
        }
        if let function = MathSymbolCatalog.functions[name] {
            return .operatorName(function.text, limits: function.limits)
        }
        if let space = Self.spaces[name] { return .space(space) }
        if let accent = MathSymbolCatalog.accents[name] {
            return .accent(try argument(), mark: accent.mark, wide: accent.wide)
        }
        if let alphabet = Self.alphabets[name] { return try styled(alphabet) }
        if let size = Self.bigSizes[name] {
            return .delimiter(try delimiter(), size: size.size, size.kind)
        }
        return try structure(name)
    }

    private mutating func structure(_ name: String) throws -> MathNode {
        switch name {
        case "frac", "dfrac", "tfrac", "cfrac":
            let style: MathNode.Style? =
                name == "dfrac" || name == "cfrac" ? .display : name == "tfrac" ? .text : nil
            return .fraction(numerator: try argument(), denominator: try argument(), rule: true, style: style)
        case "binom", "dbinom", "tbinom":
            let style: MathNode.Style? = name == "dbinom" ? .display : name == "tbinom" ? .text : nil
            let fraction = MathNode.fraction(
                numerator: try argument(), denominator: try argument(), rule: false, style: style)
            return .fenced(open: "(", body: fraction, close: ")")
        case "sqrt":
            var degree: MathNode?
            if case .character("[") = peek() {
                _ = next()
                degree = .row(try list(until: .bracket))
            }
            return .radical(try argument(), degree: degree)
        case "left":
            let open = try delimiter()
            let body = try list(until: .right)
            return .fenced(open: open, body: .row(body), close: try delimiter())
        case "text", "textrm", "textnormal", "mbox", "textit", "textbf", "textsf", "texttt", "mathnormal":
            return .text(try rawText(), .ord)
        case "operatorname":
            let star = skipStar()
            return .operatorName(try rawText(), limits: star)
        case "overline": return .overline(try argument())
        case "underline": return .underline(try argument())
        case "boxed", "fbox": return .boxed(try argument())
        case "overset", "stackrel":
            let over = try argument()
            return .stack(base: try argument(), over: over, under: nil)
        case "underset":
            let under = try argument()
            return .stack(base: try argument(), over: nil, under: under)
        case "not": return try negated()
        case "bmod": return .text("mod", .bin)
        case "pmod":
            let body = try argument()
            return .row([
                .space(18), .symbol("(", .open), .operatorName("mod", limits: false), .space(6), body,
                .symbol(")", .close)
            ])
        case "mod":
            return .row([.space(18), .operatorName("mod", limits: false), .space(6)])
        case "begin": return try environment()
        case "color":
            _ = try rawText()
            return .space(0)
        case "textcolor", "colorbox":
            _ = try rawText()
            return try argument()
        case "nonumber", "notag": return .space(0)
        case "label", "tag":
            _ = skipStar()
            _ = try rawText()
            return .space(0)
        default: throw Failure.unsupported
        }
    }

    private static let spaces: [String: Double] = [
        ",": 3, "thinspace": 3, ":": 4, ">": 4, "medspace": 4, ";": 5, "thickspace": 5, "!": -3,
        "negthinspace": -3, " ": 6, "quad": 18, "qquad": 36, "enspace": 9
    ]

    private static let alphabets: [String: MathNode.Alphabet] = [
        "mathrm": .upright, "mathup": .upright, "mathit": .italic, "mathbf": .bold,
        "boldsymbol": .boldItalic, "bm": .boldItalic, "mathbb": .doubleStruck, "mathcal": .script,
        "mathscr": .script, "mathfrak": .fraktur, "mathsf": .sansSerif, "mathtt": .monospace
    ]

    private static let bigSizes: [String: (size: Int, kind: MathNode.Kind)] = [
        "big": (1, .ord), "Big": (2, .ord), "bigg": (3, .ord), "Bigg": (4, .ord),
        "bigl": (1, .open), "Bigl": (2, .open), "biggl": (3, .open), "Biggl": (4, .open),
        "bigr": (1, .close), "Bigr": (2, .close), "biggr": (3, .close), "Biggr": (4, .close),
        "bigm": (1, .rel), "Bigm": (2, .rel), "biggm": (3, .rel), "Biggm": (4, .rel)
    ]

    private mutating func styled(_ next: MathNode.Alphabet) throws -> MathNode {
        let previous = alphabet
        alphabet = next
        defer { alphabet = previous }
        return try argument()
    }

    /// What `\left`, `\right` and `\big` size: a bracket character or a named delimiter.
    private mutating func delimiter() throws -> String {
        switch next() {
        case .character("."): return ""
        case .character("<"): return "⟨"
        case .character(">"): return "⟩"
        case .character(let character) where "()[]|/".contains(character): return String(character)
        case .command(let name):
            guard let character = MathSymbolCatalog.delimiters[name] else { throw Failure.unsupported }
            return character
        default: throw Failure.unsupported
        }
    }

    private mutating func negated() throws -> MathNode {
        guard case .symbol(let character, let kind) = try argument() else { throw Failure.unsupported }
        return .symbol(MathSymbolCatalog.negations[character] ?? character + "\u{0338}", kind)
    }

    private mutating func skipStar() -> Bool {
        guard index < characters.count, characters[index] == "*" else { return false }
        index += 1
        return true
    }

    private mutating func skipOptional() throws {
        _ = next()
        while index < characters.count, characters[index] != "]" { index += 1 }
        guard index < characters.count else { throw Failure.unsupported }
        index += 1
    }

    /// A braced group read as prose: spaces kept, only the escapes a sentence needs.
    private mutating func rawText() throws -> String {
        guard next() == .open else { throw Failure.unsupported }
        var text = ""
        var nesting = 0
        while index < characters.count {
            let character = characters[index]
            index += 1
            switch character {
            case "{": nesting += 1
            case "}":
                if nesting == 0 { return text }
                nesting -= 1
            case "\\":
                guard index < characters.count else { throw Failure.unsupported }
                let escaped = characters[index]
                index += 1
                guard "{}$&%#_ ,;".contains(escaped) else { throw Failure.unsupported }
                text.append(",;".contains(escaped) ? " " : escaped)
            case "$": throw Failure.unsupported
            default: text.append(character.isNewline ? " " : character)
            }
        }
        throw Failure.unsupported
    }

    // MARK: Environments

    private mutating func environment() throws -> MathNode {
        let name = try rawText()
        let layout = try Self.tableLayout(name, columns: try columnSpec(for: name))
        let rows = try cells()
        guard next() == .command("end"), try rawText() == name else { throw Failure.unsupported }
        var styledRows = rows.map { $0.map(MathNode.row) }
        if layout.alignments == [.trailing, .leading] {
            // Aligned's right halves start with `{}`, so `&=` spaces its relation as TeX does.
            styledRows = rows.map { row in
                row.enumerated().map { column, cell in
                    .row(column % 2 == 1 ? [.row([])] + cell : cell)
                }
            }
        }
        let table = MathNode.table(
            .init(rows: styledRows, alignments: layout.alignments, gaps: layout.gaps, style: layout.style))
        guard let fences = Self.fences[name] else { return table }
        return .fenced(open: fences.open, body: table, close: fences.close)
    }

    private static let fences: [String: (open: String, close: String)] = [
        "pmatrix": ("(", ")"), "bmatrix": ("[", "]"), "Bmatrix": ("{", "}"), "vmatrix": ("|", "|"),
        "Vmatrix": ("‖", "‖"), "cases": ("{", ""), "dcases": ("{", ""), "rcases": ("", "}")
    ]

    private static func tableLayout(
        _ name: String, columns: [MathNode.Table.Alignment]?
    ) throws
        -> (alignments: [MathNode.Table.Alignment], gaps: [Double], style: MathNode.Style)
    {
        switch name {
        case "matrix", "pmatrix", "bmatrix", "Bmatrix", "vmatrix", "Vmatrix":
            return ([.center], [18], .text)
        case "smallmatrix": return ([.center], [9], .script)
        case "cases", "rcases": return ([.leading], [18], .text)
        case "dcases": return ([.leading], [18], .display)
        case "aligned", "align", "align*", "split", "alignat", "alignat*", "flalign", "flalign*":
            return ([.trailing, .leading], [0, 36], .display)
        case "gathered", "gather", "gather*", "equation", "equation*", "multline", "multline*":
            return ([.center], [0], .display)
        case "array":
            guard let columns else { throw Failure.unsupported }
            return (columns, [18], .text)
        default: throw Failure.unsupported
        }
    }

    /// `array`'s `{lcr}`; vertical rules are dropped rather than refused.
    private mutating func columnSpec(for name: String) throws -> [MathNode.Table.Alignment]? {
        guard name == "array" else {
            if name.hasPrefix("alignat") { _ = try rawText() }
            return nil
        }
        let columns = try rawText().compactMap { character -> MathNode.Table.Alignment? in
            switch character {
            case "l": .leading
            case "c": .center
            case "r": .trailing
            default: nil
            }
        }
        guard !columns.isEmpty else { throw Failure.unsupported }
        return columns
    }
}
