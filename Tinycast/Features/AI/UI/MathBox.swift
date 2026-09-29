import AppKit

/// A laid-out piece of a formula: its extent about the baseline and what to draw, y pointing up.
struct MathBox {
    enum Mark {
        case glyphs(CTFont, [CGGlyph], [CGPoint])
        case rule(CGRect)
    }

    var width: CGFloat = 0
    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    /// How far a slanted last glyph overhangs its advance, which a superscript clears.
    var italicCorrection: CGFloat = 0
    private(set) var marks: [Mark] = []

    var height: CGFloat { ascent + descent }

    init(width: CGFloat = 0, ascent: CGFloat = 0, descent: CGFloat = 0) {
        self.width = width
        self.ascent = ascent
        self.descent = descent
    }

    /// One glyph, measured by its ink so a script sits against what is drawn, not the line box.
    init(glyph: CGGlyph, font: CTFont) {
        var glyph = glyph
        var ink = CGRect.zero
        var advance = CGSize.zero
        CTFontGetBoundingRectsForGlyphs(font, .default, &glyph, &ink, 1)
        CTFontGetAdvancesForGlyphs(font, .default, &glyph, &advance, 1)
        width = advance.width
        ascent = max(ink.maxY, 0)
        descent = max(-ink.minY, 0)
        marks = [.glyphs(font, [glyph], [.zero])]
    }

    /// A run of text through Core Text, which falls back to another font for what STIX lacks.
    init(text: String, font: CTFont) {
        let attributed = NSAttributedString(
            string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(attributed)
        width = CTLineGetTypographicBounds(line, nil, nil, nil)
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        if !ink.isNull {
            ascent = max(ink.maxY, 0)
            descent = max(-ink.minY, 0)
        }
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(), &glyphs)
            CTRunGetPositions(run, CFRange(), &positions)
            let fallback = (CTRunGetAttributes(run) as? [NSAttributedString.Key: Any])?[.font] as? NSFont
            marks.append(.glyphs(fallback.map { $0 as CTFont } ?? font, glyphs, positions))
        }
    }

    static func rule(_ rect: CGRect) -> MathBox {
        var box = MathBox(width: rect.maxX, ascent: max(rect.maxY, 0), descent: max(-rect.minY, 0))
        box.marks = [.rule(rect)]
        return box
    }

    /// Draws `box` with its baseline origin at `x, y`, growing this box to hold it.
    mutating func place(_ box: MathBox, x: CGFloat, y: CGFloat = 0) {
        width = max(width, x + box.width)
        ascent = max(ascent, y + box.ascent)
        descent = max(descent, box.descent - y)
        for mark in box.marks {
            switch mark {
            case .glyphs(let font, let glyphs, let positions):
                marks.append(.glyphs(font, glyphs, positions.map { CGPoint(x: $0.x + x, y: $0.y + y) }))
            case .rule(let rect):
                marks.append(.rule(rect.offsetBy(dx: x, dy: y)))
            }
        }
    }

    /// The same drawing moved up by `shift`, as centring a delimiter on the math axis needs.
    func raised(by shift: CGFloat) -> MathBox {
        var raised = MathBox(width: width)
        raised.place(self, x: 0, y: shift)
        raised.ascent = ascent + shift
        raised.descent = descent - shift
        raised.italicCorrection = italicCorrection
        return raised
    }

    /// Fills with the context's current fill colour, from a y-up origin on the baseline.
    func draw(in context: CGContext) {
        context.textMatrix = .identity
        for mark in marks {
            switch mark {
            case .glyphs(let font, let glyphs, let positions):
                CTFontDrawGlyphs(font, glyphs, positions, glyphs.count, context)
            case .rule(let rect):
                context.fill(rect)
            }
        }
    }
}
