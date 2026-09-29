import AppKit

/// Typesets a parsed formula in STIX Two Math, by TeX's rules as the font's MATH table states them.
struct MathLayoutEngine {
    /// Text, script and script-script sizes, in the order `Style.fontIndex` reads them.
    private let fonts: [MathFont]

    /// Nil when the system's math font is missing, which leaves every formula as its source.
    init?(size: CGFloat) {
        guard let text = MathFont(size: size),
            let script = MathFont(size: size * text.value(.scriptPercentScaleDown) / 100),
            let scriptScript = MathFont(size: size * text.value(.scriptScriptPercentScaleDown) / 100)
        else { return nil }
        fonts = [text, script, scriptScript]
    }

    func layout(_ formula: MathFormula) -> MathBox {
        layout(formula.root, Environment(style: formula.display ? .display : .text, cramped: false))
    }

    /// TeX's style and crampedness: what shrinks a script and how high it may ride.
    private struct Environment {
        var style: MathNode.Style
        var cramped: Bool

        var superscript: Environment { .init(style: style.script, cramped: cramped) }
        var `subscript`: Environment { .init(style: style.script, cramped: true) }
        var numerator: Environment { .init(style: style.fractionPart, cramped: cramped) }
        var denominator: Environment { .init(style: style.fractionPart, cramped: true) }
        var squeezed: Environment { .init(style: style, cramped: true) }
    }

    private func font(_ environment: Environment) -> MathFont {
        fonts[environment.style.fontIndex]
    }

    private func layout(_ node: MathNode, _ environment: Environment) -> MathBox {
        let font = font(environment)
        switch node {
        case .symbol(let character, _): return symbol(character, font)
        case .text(let text, _), .operatorName(let text, _): return MathBox(text: text, font: font.font)
        case .largeOperator(let character, _): return largeOperator(character, environment)
        case .row(let nodes): return row(nodes, environment)
        case .scripts(let base, let superscript, let `subscript`):
            return scripts(base, superscript, `subscript`, environment)
        case .stack(let base, let over, let under):
            return limits(layout(base, environment), over: over, under: under, environment)
        case .fraction(let numerator, let denominator, let rule, let style):
            var inner = environment
            if let style { inner.style = style }
            return fraction(numerator, denominator, rule: rule, inner)
        case .radical(let body, let degree): return radical(body, degree: degree, environment)
        case .fenced(let open, let body, let close):
            return fenced(open: open, body: layout(body, environment), close: close, font)
        case .delimiter(let character, let size, _):
            return delimiter(character, height: Self.bigHeights[size - 1] * font.size, font)
        case .accent(let base, let mark, let wide): return accent(base, mark: mark, wide: wide, environment)
        case .overline(let body): return overline(layout(body, environment.squeezed), font)
        case .underline(let body): return underline(layout(body, environment), font)
        case .boxed(let body): return boxed(layout(body, environment), font)
        case .space(let mu): return MathBox(width: mu * font.size / 18)
        case .styled(let style, let body):
            return layout(body, Environment(style: style, cramped: environment.cramped))
        case .table(let table): return self.table(table, environment)
        }
    }

    /// `\big` to `\Bigg`, in ems, as KaTeX sizes them.
    private static let bigHeights: [CGFloat] = [1.2, 1.8, 2.4, 3.0]

    private func symbol(_ character: String, _ font: MathFont) -> MathBox {
        guard character.unicodeScalars.count == 1, let glyph = font.glyph(for: character) else {
            return MathBox(text: character, font: font.font)
        }
        var box = MathBox(glyph: glyph, font: font.font)
        box.italicCorrection = font.italicCorrection(glyph)
        return box
    }

    // MARK: Rows and spacing

    private func row(_ nodes: [MathNode], _ environment: Environment) -> MathBox {
        var box = MathBox()
        var x: CGFloat = 0
        var previous: MathNode.Kind?
        for (node, kind) in zip(nodes, Self.spacingKinds(nodes)) {
            if let kind, let previous { x += space(between: previous, and: kind, environment) }
            let child = layout(node, environment)
            box.place(child, x: x)
            x += child.width
            box.italicCorrection = child.italicCorrection
            if let kind { previous = kind }
        }
        box.width = max(x, 0)
        return box
    }

    /// TeX's rule that a binary operator with nothing to join, like a leading minus, is ordinary.
    private static func spacingKinds(_ nodes: [MathNode]) -> [MathNode.Kind?] {
        var kinds = nodes.map(kind(of:))
        let unary: Set<MathNode.Kind> = [.bin, .op, .rel, .open, .punct]
        let closing: Set<MathNode.Kind> = [.rel, .close, .punct]
        var previous: Int?
        for index in kinds.indices {
            guard let current = kinds[index] else { continue }
            let before = previous.flatMap { kinds[$0] }
            if current == .bin, before.map(unary.contains) ?? true { kinds[index] = .ord }
            if closing.contains(current), let previous, kinds[previous] == .bin { kinds[previous] = .ord }
            previous = index
        }
        if let previous, kinds[previous] == .bin { kinds[previous] = .ord }
        return kinds
    }

    private static func kind(of node: MathNode) -> MathNode.Kind? {
        switch node {
        case .symbol(_, let kind), .text(_, let kind), .delimiter(_, _, let kind): kind
        case .operatorName, .largeOperator: .op
        case .scripts(let base, _, _), .stack(let base, _, _): kind(of: base) ?? .ord
        case .fraction, .fenced: .inner
        case .space: nil
        default: .ord
        }
    }

    /// TeX's inter-atom table in mu; a negative entry applies only outside script styles.
    private static let spacing: [[CGFloat]] = [
        [0, 3, -4, -5, 0, 0, 0, -3],
        [3, 3, 0, -5, 0, 0, 0, -3],
        [-4, -4, 0, 0, -4, 0, 0, -4],
        [-5, -5, 0, 0, -5, 0, 0, -5],
        [0, 0, 0, 0, 0, 0, 0, 0],
        [0, 3, -4, -5, 0, 0, 0, -3],
        [-3, -3, 0, -3, -3, -3, -3, -3],
        [-3, 3, -4, -5, -3, 0, -3, -3]
    ]

    private func space(
        between left: MathNode.Kind, and right: MathNode.Kind, _ environment: Environment
    )
        -> CGFloat
    {
        let mu = Self.spacing[left.tableIndex][right.tableIndex]
        let isScript = environment.style == .script || environment.style == .scriptScript
        guard mu > 0 || !isScript else { return 0 }
        return abs(mu) * font(environment).size / 18
    }

    // MARK: Operators and scripts

    private func largeOperator(_ character: String, _ environment: Environment) -> MathBox {
        let font = font(environment)
        guard let glyph = font.glyph(for: character) else { return MathBox(text: character, font: font.font) }
        var chosen = glyph
        if environment.style == .display {
            let minimum = font.value(.displayOperatorMinHeight)
            let variants = font.verticalVariants(glyph)
            chosen =
                variants.first { MathBox(glyph: $0, font: font.font).height >= minimum } ?? variants.last
                ?? glyph
        }
        var box = MathBox(glyph: chosen, font: font.font)
        box.italicCorrection = font.italicCorrection(chosen)
        return centred(box, font)
    }

    private func scripts(
        _ base: MathNode, _ superscript: MathNode?, _ `subscript`: MathNode?, _ environment: Environment
    ) -> MathBox {
        let nucleus = layout(base, environment)
        if environment.style == .display, Self.takesLimits(base) {
            return limits(nucleus, over: superscript, under: `subscript`, environment)
        }
        let font = font(environment)
        let isGlyph = Self.isSingleGlyph(base)
        let upper = superscript.map { layout($0, environment.superscript) }
        let lower = `subscript`.map { layout($0, environment.subscript) }
        var up: CGFloat = 0
        var down: CGFloat = 0
        if let upper {
            let shift = font.value(environment.cramped ? .superscriptShiftUpCramped : .superscriptShiftUp)
            up = max(shift, upper.descent + font.value(.superscriptBottomMin))
            if !isGlyph { up = max(up, nucleus.ascent - font.value(.superscriptBaselineDropMax)) }
        }
        if let lower {
            down = max(font.value(.subscriptShiftDown), lower.ascent - font.value(.subscriptTopMax))
            if !isGlyph { down = max(down, nucleus.descent + font.value(.subscriptBaselineDropMin)) }
        }
        if let upper, let lower {
            let gap = (up - upper.descent) - (lower.ascent - down)
            let minimum = font.value(.subSuperscriptGapMin)
            if gap < minimum {
                down += minimum - gap
                let lift = font.value(.superscriptBottomMaxWithSubscript) - (up - upper.descent)
                if lift > 0 {
                    up += lift
                    down -= lift
                }
            }
        }
        // An operator's overhang pulls its subscript in; a letter's pushes its superscript out.
        let isOperator = if case .largeOperator = base { true } else { false }
        let italic = nucleus.italicCorrection
        var box = MathBox()
        box.place(nucleus, x: 0)
        var end = nucleus.width
        if let upper {
            let x = nucleus.width + (isOperator ? 0 : italic)
            box.place(upper, x: x, y: up)
            end = max(end, x + upper.width)
        }
        if let lower {
            let x = nucleus.width - (isOperator ? italic : 0)
            box.place(lower, x: x, y: -down)
            end = max(end, x + lower.width)
        }
        box.width = end + font.value(.spaceAfterScript)
        return box
    }

    private static func takesLimits(_ node: MathNode) -> Bool {
        switch node {
        case .largeOperator(_, let limits), .operatorName(_, let limits): limits
        default: false
        }
    }

    /// A lone character keeps the font's script shifts; any other base, operators too, drops them.
    private static func isSingleGlyph(_ node: MathNode) -> Bool {
        if case .symbol = node { return true }
        return false
    }

    private func limits(
        _ nucleus: MathBox, over: MathNode?, under: MathNode?, _ environment: Environment
    )
        -> MathBox
    {
        let font = font(environment)
        let upper = over.map { layout($0, environment.superscript) }
        let lower = under.map { layout($0, environment.subscript) }
        let width = max(nucleus.width, upper?.width ?? 0, lower?.width ?? 0)
        let italic = nucleus.italicCorrection
        var box = MathBox()
        box.place(nucleus, x: (width - nucleus.width) / 2)
        if let upper {
            let rise = max(
                font.value(.upperLimitBaselineRiseMin), font.value(.upperLimitGapMin) + upper.descent)
            box.place(upper, x: (width - upper.width + italic) / 2, y: nucleus.ascent + rise)
        }
        if let lower {
            let drop = max(
                font.value(.lowerLimitBaselineDropMin), font.value(.lowerLimitGapMin) + lower.ascent)
            box.place(lower, x: (width - lower.width - italic) / 2, y: -(nucleus.descent + drop))
        }
        box.width = width
        return box
    }

    // MARK: Fractions and radicals

    private func fraction(
        _ numerator: MathNode, _ denominator: MathNode, rule: Bool, _ environment: Environment
    )
        -> MathBox
    {
        let font = font(environment)
        let isDisplay = environment.style == .display
        let top = layout(numerator, environment.numerator)
        let bottom = layout(denominator, environment.denominator)
        let axis = font.value(.axisHeight)
        let thickness = rule ? font.value(.fractionRuleThickness) : 0
        var up: CGFloat
        var down: CGFloat
        if rule {
            up = font.value(isDisplay ? .fractionNumeratorDisplayStyleShiftUp : .fractionNumeratorShiftUp)
            down = font.value(
                isDisplay ? .fractionDenominatorDisplayStyleShiftDown : .fractionDenominatorShiftDown)
            let above = font.value(isDisplay ? .fractionNumDisplayStyleGapMin : .fractionNumeratorGapMin)
            let below = font.value(isDisplay ? .fractionDenomDisplayStyleGapMin : .fractionDenominatorGapMin)
            up = max(up, axis + thickness / 2 + above + top.descent)
            down = max(down, bottom.ascent + below + thickness / 2 - axis)
        } else {
            up = font.value(isDisplay ? .stackTopDisplayStyleShiftUp : .stackTopShiftUp)
            down = font.value(isDisplay ? .stackBottomDisplayStyleShiftDown : .stackBottomShiftDown)
            let minimum = font.value(isDisplay ? .stackDisplayStyleGapMin : .stackGapMin)
            let gap = (up - top.descent) - (bottom.ascent - down)
            if gap < minimum {
                up += (minimum - gap) / 2
                down += (minimum - gap) / 2
            }
        }
        // TeX's null delimiter space, so a bar never runs into its neighbours.
        let padding = font.size * 0.12
        let width = max(top.width, bottom.width)
        var box = MathBox()
        box.place(top, x: padding + (width - top.width) / 2, y: up)
        box.place(bottom, x: padding + (width - bottom.width) / 2, y: -down)
        if rule {
            box.place(
                .rule(CGRect(x: padding, y: axis - thickness / 2, width: width, height: thickness)), x: 0)
        }
        box.width = width + padding * 2
        return box
    }

    private func radical(_ body: MathNode, degree: MathNode?, _ environment: Environment) -> MathBox {
        let font = font(environment)
        let inner = layout(body, environment.squeezed)
        let thickness = font.value(.radicalRuleThickness)
        var gap = font.value(
            environment.style == .display ? .radicalDisplayStyleVerticalGap : .radicalVerticalGap)
        let sign = stretched("√", height: inner.height + gap + thickness, font)
        gap += max(sign.height - (inner.height + gap + thickness), 0) / 2
        let top = inner.ascent + gap + thickness
        let signShift = top - sign.ascent
        var box = MathBox()
        var x: CGFloat = 0
        if let degree {
            let index = layout(degree, Environment(style: .scriptScript, cramped: true))
            let raise = font.value(.radicalDegreeBottomRaisePercent) / 100 * sign.height
            let before = font.value(.radicalKernBeforeDegree)
            box.place(index, x: before, y: signShift - sign.descent + raise)
            x = max(before + index.width + font.value(.radicalKernAfterDegree), 0)
        }
        box.place(sign, x: x, y: signShift)
        x += sign.width
        box.place(.rule(CGRect(x: x, y: inner.ascent + gap, width: inner.width, height: thickness)), x: 0)
        box.place(inner, x: x)
        box.width = x + inner.width
        box.ascent = max(box.ascent, top + font.value(.radicalExtraAscender))
        return box
    }

    // MARK: Delimiters

    private func fenced(open: String, body: MathBox, close: String, _ font: MathFont) -> MathBox {
        let axis = font.value(.axisHeight)
        let reach = max(body.ascent - axis, body.descent + axis)
        // TeX's delimiter factor and shortfall: cover 90% of the body, or all but half an em.
        let height = max(2 * reach * 0.901, 2 * reach - font.size * 0.5)
        let left = delimiter(open, height: height, font)
        let right = delimiter(close, height: height, font)
        var box = MathBox()
        box.place(left, x: 0)
        box.place(body, x: left.width)
        box.place(right, x: left.width + body.width)
        box.width = left.width + body.width + right.width
        return box
    }

    private func delimiter(_ character: String, height: CGFloat, _ font: MathFont) -> MathBox {
        guard !character.isEmpty else { return MathBox(width: font.size * 0.12) }
        return centred(stretched(character, height: height, font), font)
    }

    private func centred(_ box: MathBox, _ font: MathFont) -> MathBox {
        box.raised(by: font.value(.axisHeight) - (box.ascent - box.descent) / 2)
    }

    /// The first variant at least `height` tall, else the font's assembly of repeatable pieces.
    private func stretched(_ character: String, height: CGFloat, _ font: MathFont) -> MathBox {
        guard let glyph = font.glyph(for: character) else { return MathBox(text: character, font: font.font) }
        var largest = MathBox(glyph: glyph, font: font.font)
        for variant in font.verticalVariants(glyph) {
            largest = MathBox(glyph: variant, font: font.font)
            if largest.height >= height { return largest }
        }
        return assembled(glyph, height: height, font) ?? largest
    }

    private func assembled(_ glyph: CGGlyph, height: CGFloat, _ font: MathFont) -> MathBox? {
        let parts = font.verticalAssembly(glyph)
        guard parts.contains(where: \.isExtender) else { return nil }
        let overlap = font.minConnectorOverlap
        func sequence(_ repeats: Int) -> [MathFont.Part] {
            parts.flatMap { $0.isExtender ? Array(repeating: $0, count: repeats) : [$0] }
        }
        func reach(_ pieces: [MathFont.Part]) -> CGFloat {
            pieces.reduce(0) { $0 + $1.fullAdvance } - overlap * CGFloat(max(pieces.count - 1, 0))
        }
        var repeats = 1
        while reach(sequence(repeats)) < height, repeats < Self.maximumRepeats { repeats += 1 }
        var box = MathBox()
        var y: CGFloat = 0
        for part in sequence(repeats) {
            let piece = MathBox(glyph: part.glyph, font: font.font)
            box.place(piece, x: 0, y: y + piece.descent)
            y += part.fullAdvance - overlap
        }
        return box
    }

    /// Bounds a hostile `\left(` around thousands of rows to a finite number of glyphs.
    private static let maximumRepeats = 200

    // MARK: Accents, bars and boxes

    private func accent(_ base: MathNode, mark: String, wide: Bool, _ environment: Environment) -> MathBox {
        let font = font(environment)
        let nucleus = layout(base, environment.squeezed)
        guard let markGlyph = font.glyph(for: mark) else { return nucleus }
        var glyph = markGlyph
        if wide {
            for variant in font.horizontalVariants(markGlyph) {
                glyph = variant
                if MathBox(glyph: variant, font: font.font).width >= nucleus.width { break }
            }
        }
        var ink = CGRect.zero
        var measured = glyph
        CTFontGetBoundingRectsForGlyphs(font.font, .default, &measured, &ink, 1)
        let baseGlyph: CGGlyph? =
            if case .symbol(let character, _) = base { font.glyph(for: character) } else { nil }
        let baseAttachment = baseGlyph.flatMap(font.topAccentAttachment) ?? nucleus.width / 2
        let markAttachment = font.topAccentAttachment(glyph) ?? ink.midX
        var box = MathBox()
        box.place(nucleus, x: 0)
        box.place(
            MathBox(glyph: glyph, font: font.font), x: baseAttachment - markAttachment,
            y: max(nucleus.ascent - font.value(.accentBaseHeight), 0))
        box.width = nucleus.width
        box.italicCorrection = nucleus.italicCorrection
        return box
    }

    private func overline(_ body: MathBox, _ font: MathFont) -> MathBox {
        let thickness = font.value(.overbarRuleThickness)
        var box = MathBox()
        box.place(body, x: 0)
        let y = body.ascent + font.value(.overbarVerticalGap)
        box.place(.rule(CGRect(x: 0, y: y, width: body.width, height: thickness)), x: 0)
        box.ascent = y + thickness + font.value(.overbarExtraAscender)
        box.width = body.width
        return box
    }

    private func underline(_ body: MathBox, _ font: MathFont) -> MathBox {
        let thickness = font.value(.underbarRuleThickness)
        var box = MathBox()
        box.place(body, x: 0)
        let y = -(body.descent + font.value(.underbarVerticalGap) + thickness)
        box.place(.rule(CGRect(x: 0, y: y, width: body.width, height: thickness)), x: 0)
        box.descent = -y + font.value(.underbarExtraDescender)
        box.width = body.width
        return box
    }

    private func boxed(_ body: MathBox, _ font: MathFont) -> MathBox {
        let padding = font.size * 0.25
        let thickness = font.value(.fractionRuleThickness)
        let inset = padding + thickness
        let frame = CGRect(
            x: 0, y: -(body.descent + inset), width: body.width + inset * 2, height: body.height + inset * 2)
        var box = MathBox()
        box.place(body, x: inset)
        for edge in [
            CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: thickness),
            CGRect(x: frame.minX, y: frame.maxY - thickness, width: frame.width, height: thickness),
            CGRect(x: frame.minX, y: frame.minY, width: thickness, height: frame.height),
            CGRect(x: frame.maxX - thickness, y: frame.minY, width: thickness, height: frame.height)
        ] {
            box.place(.rule(edge), x: 0)
        }
        box.width = frame.width
        return box
    }

    // MARK: Tables

    private func table(_ table: MathNode.Table, _ environment: Environment) -> MathBox {
        let inner = Environment(style: table.style, cramped: environment.cramped)
        let font = font(inner)
        let cells = table.rows.map { $0.map { layout($0, inner) } }
        let columns = cells.map(\.count).max() ?? 0
        guard columns > 0 else { return MathBox() }
        var widths = [CGFloat](repeating: 0, count: columns)
        for row in cells {
            for (column, cell) in row.enumerated() { widths[column] = max(widths[column], cell.width) }
        }
        var starts: [CGFloat] = []
        var x: CGFloat = 0
        for column in 0..<columns {
            starts.append(x)
            x += widths[column]
            if column < columns - 1 { x += table.gaps[column % table.gaps.count] * font.size / 18 }
        }
        // TeX's array strut, 1.2em a row, and a display table's extra 0.3em between rows.
        let strutAscent = font.size * 0.84
        let strutDescent = font.size * 0.36
        let jot = table.style == .display ? font.size * 0.3 : 0
        var baselines: [CGFloat] = []
        var y: CGFloat = 0
        var bottom: CGFloat = 0
        for (index, row) in cells.enumerated() {
            let ascent = max(row.map(\.ascent).max() ?? 0, strutAscent)
            let descent = max(row.map(\.descent).max() ?? 0, strutDescent)
            if index > 0 { y -= ascent + jot }
            baselines.append(y)
            y -= descent
            bottom = y
        }
        let top = max(cells.first?.map(\.ascent).max() ?? 0, strutAscent)
        let shift = font.value(.axisHeight) - (top + bottom) / 2
        var box = MathBox()
        for (row, baseline) in zip(cells, baselines) {
            for (column, cell) in row.enumerated() {
                let slack = widths[column] - cell.width
                let offset: CGFloat =
                    switch table.alignments[column % table.alignments.count] {
                    case .leading: 0
                    case .center: slack / 2
                    case .trailing: slack
                    }
                box.place(cell, x: starts[column] + offset, y: baseline + shift)
            }
        }
        box.width = x
        box.ascent = max(box.ascent, top + shift)
        box.descent = max(box.descent, -(bottom + shift))
        return box
    }
}

extension MathNode.Style {
    fileprivate var fontIndex: Int {
        switch self {
        case .display, .text: 0
        case .script: 1
        case .scriptScript: 2
        }
    }

    fileprivate var script: Self {
        switch self {
        case .display, .text: .script
        case .script, .scriptScript: .scriptScript
        }
    }

    fileprivate var fractionPart: Self {
        switch self {
        case .display: .text
        case .text: .script
        case .script, .scriptScript: .scriptScript
        }
    }
}

extension MathNode.Kind {
    fileprivate var tableIndex: Int {
        switch self {
        case .ord: 0
        case .op: 1
        case .bin: 2
        case .rel: 3
        case .open: 4
        case .close: 5
        case .punct: 6
        case .inner: 7
        }
    }
}
