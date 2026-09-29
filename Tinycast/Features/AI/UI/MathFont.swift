import CoreText
import Foundation

/// STIX Two Math, which macOS ships, at one size, read through its OpenType MATH table.
struct MathFont {
    /// The MATH table's layout constants, each named by its byte offset in `MathConstants`.
    enum Constant: Int, CaseIterable {
        case scriptPercentScaleDown = 0
        case scriptScriptPercentScaleDown = 2
        case displayOperatorMinHeight = 6
        case axisHeight = 12
        case accentBaseHeight = 16
        case subscriptShiftDown = 24
        case subscriptTopMax = 28
        case subscriptBaselineDropMin = 32
        case superscriptShiftUp = 36
        case superscriptShiftUpCramped = 40
        case superscriptBottomMin = 44
        case superscriptBaselineDropMax = 48
        case subSuperscriptGapMin = 52
        case superscriptBottomMaxWithSubscript = 56
        case spaceAfterScript = 60
        case upperLimitGapMin = 64
        case upperLimitBaselineRiseMin = 68
        case lowerLimitGapMin = 72
        case lowerLimitBaselineDropMin = 76
        case stackTopShiftUp = 80
        case stackTopDisplayStyleShiftUp = 84
        case stackBottomShiftDown = 88
        case stackBottomDisplayStyleShiftDown = 92
        case stackGapMin = 96
        case stackDisplayStyleGapMin = 100
        case fractionNumeratorShiftUp = 120
        case fractionNumeratorDisplayStyleShiftUp = 124
        case fractionDenominatorShiftDown = 128
        case fractionDenominatorDisplayStyleShiftDown = 132
        case fractionNumeratorGapMin = 136
        case fractionNumDisplayStyleGapMin = 140
        case fractionRuleThickness = 144
        case fractionDenominatorGapMin = 148
        case fractionDenomDisplayStyleGapMin = 152
        case overbarVerticalGap = 164
        case overbarRuleThickness = 168
        case overbarExtraAscender = 172
        case underbarVerticalGap = 176
        case underbarRuleThickness = 180
        case underbarExtraDescender = 184
        case radicalVerticalGap = 188
        case radicalDisplayStyleVerticalGap = 192
        case radicalRuleThickness = 196
        case radicalExtraAscender = 200
        case radicalKernBeforeDegree = 204
        case radicalKernAfterDegree = 208
        case radicalDegreeBottomRaisePercent = 212

        /// The three that are percentages rather than lengths in font units.
        var isPercent: Bool {
            switch self {
            case .scriptPercentScaleDown, .scriptScriptPercentScaleDown, .radicalDegreeBottomRaisePercent:
                true
            default: false
            }
        }
    }

    struct Part {
        let glyph: CGGlyph
        let startConnector: CGFloat
        let endConnector: CGFloat
        let fullAdvance: CGFloat
        let isExtender: Bool
    }

    static let postScriptName = "STIXTwoMath-Regular"

    let font: CTFont
    let size: CGFloat
    private let table: MathTable
    private let scale: CGFloat

    /// Nil only if the system font or its MATH table is missing, and then formulas show as source.
    init?(size: CGFloat) {
        guard let table = Self.table else { return nil }
        self.table = table
        self.size = size
        font = CTFontCreateWithName(Self.postScriptName as CFString, size, nil)
        scale = size / CGFloat(table.unitsPerEm)
    }

    /// Parsed once, on the first formula, and never on launch.
    private static let table: MathTable? = MathTable(
        CTFontCreateWithName(postScriptName as CFString, 12, nil))

    /// The size at which STIX's x-height equals `font`'s, so a formula reads at the text's scale.
    static func size(matchingXHeightOf font: CTFont) -> CGFloat {
        let ratio = CTFontGetXHeight(font) / xHeightPerPoint
        return ratio > 0 ? ratio : CTFontGetSize(font)
    }

    private static let xHeightPerPoint = max(
        CTFontGetXHeight(CTFontCreateWithName(postScriptName as CFString, 1, nil)), 0.01)

    func value(_ constant: Constant) -> CGFloat {
        let raw = CGFloat(table.constants[constant] ?? 0)
        return constant.isPercent ? raw : raw * scale
    }

    var minConnectorOverlap: CGFloat { CGFloat(table.minConnectorOverlap) * scale }

    func glyph(for character: String) -> CGGlyph? {
        let units = Array(character.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        guard CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count), glyphs[0] != 0 else {
            return nil
        }
        return glyphs[0]
    }

    func italicCorrection(_ glyph: CGGlyph) -> CGFloat {
        CGFloat(table.italicCorrections[glyph] ?? 0) * scale
    }

    func topAccentAttachment(_ glyph: CGGlyph) -> CGFloat? {
        table.topAccentAttachments[glyph].map { CGFloat($0) * scale }
    }

    /// Taller versions of a glyph, smallest first, starting with the glyph itself.
    func verticalVariants(_ glyph: CGGlyph) -> [CGGlyph] {
        [glyph] + (table.vertical[glyph]?.variants ?? [])
    }

    func horizontalVariants(_ glyph: CGGlyph) -> [CGGlyph] {
        [glyph] + (table.horizontal[glyph]?.variants ?? [])
    }

    /// Pieces that stack to any height, bottom first: a brace's hooks, middle and extenders.
    func verticalAssembly(_ glyph: CGGlyph) -> [Part] {
        (table.vertical[glyph]?.parts ?? []).map { part in
            Part(
                glyph: part.glyph, startConnector: CGFloat(part.startConnector) * scale,
                endConnector: CGFloat(part.endConnector) * scale,
                fullAdvance: CGFloat(part.fullAdvance) * scale, isExtender: part.isExtender)
        }
    }
}

/// The parts of the MATH table the layout reads, in font units.
private struct MathTable {
    struct Construction {
        var variants: [CGGlyph] = []
        var parts: [RawPart] = []
    }

    struct RawPart {
        let glyph: CGGlyph
        let startConnector: UInt16
        let endConnector: UInt16
        let fullAdvance: UInt16
        let isExtender: Bool
    }

    let unitsPerEm: UInt32
    let constants: [MathFont.Constant: Int16]
    let italicCorrections: [CGGlyph: Int16]
    let topAccentAttachments: [CGGlyph: Int16]
    let vertical: [CGGlyph: Construction]
    let horizontal: [CGGlyph: Construction]
    let minConnectorOverlap: UInt16

    init?(_ font: CTFont) {
        let tag = CTFontTableTag(0x4D41_5448)
        guard let data = CTFontCopyTable(font, tag, []) as Data? else { return nil }
        let bytes = BigEndianBytes(Array(data))
        let constantsOffset = bytes.offset(at: 4)
        let glyphInfo = bytes.offset(at: 6)
        let variants = bytes.offset(at: 8)
        guard constantsOffset > 0, glyphInfo > 0, variants > 0 else { return nil }
        unitsPerEm = CTFontGetUnitsPerEm(font)
        var constants: [MathFont.Constant: Int16] = [:]
        for constant in MathFont.Constant.allCases {
            constants[constant] = bytes.int16(at: constantsOffset + constant.rawValue)
        }
        self.constants = constants
        italicCorrections = Self.values(bytes, at: glyphInfo, table: bytes.offset(at: glyphInfo))
        topAccentAttachments = Self.values(bytes, at: glyphInfo, table: bytes.offset(at: glyphInfo + 2))
        minConnectorOverlap = bytes.uint16(at: variants)
        let verticalCoverage = Self.coverage(bytes, at: variants + bytes.offset(at: variants + 2))
        let horizontalCoverage = Self.coverage(bytes, at: variants + bytes.offset(at: variants + 4))
        let verticalCount = Int(bytes.uint16(at: variants + 6))
        vertical = Self.constructions(
            bytes, variants: variants, coverage: verticalCoverage, first: variants + 10,
            count: verticalCount)
        horizontal = Self.constructions(
            bytes, variants: variants, coverage: horizontalCoverage,
            first: variants + 10 + verticalCount * 2, count: Int(bytes.uint16(at: variants + 8)))
    }

    /// An italics-correction or top-accent table: a coverage, then one value record per glyph.
    private static func values(
        _ bytes: BigEndianBytes, at base: Int, table offset: Int
    )
        -> [CGGlyph: Int16]
    {
        guard offset > 0 else { return [:] }
        let start = base + offset
        let glyphs = coverage(bytes, at: start + bytes.offset(at: start))
        var values: [CGGlyph: Int16] = [:]
        for (index, glyph) in glyphs.enumerated() {
            values[glyph] = bytes.int16(at: start + 4 + index * 4)
        }
        return values
    }

    private static func constructions(
        _ bytes: BigEndianBytes, variants: Int, coverage: [CGGlyph], first: Int, count: Int
    ) -> [CGGlyph: Construction] {
        var constructions: [CGGlyph: Construction] = [:]
        for (index, glyph) in coverage.prefix(count).enumerated() {
            let start = variants + bytes.offset(at: first + index * 2)
            var construction = Construction()
            let variantCount = Int(bytes.uint16(at: start + 2))
            for variant in 0..<variantCount {
                let record = bytes.uint16(at: start + 4 + variant * 4)
                if record != glyph { construction.variants.append(record) }
            }
            let assembly = bytes.offset(at: start)
            if assembly > 0 {
                let base = start + assembly
                for part in 0..<Int(bytes.uint16(at: base + 4)) {
                    let record = base + 6 + part * 10
                    construction.parts.append(
                        RawPart(
                            glyph: bytes.uint16(at: record), startConnector: bytes.uint16(at: record + 2),
                            endConnector: bytes.uint16(at: record + 4),
                            fullAdvance: bytes.uint16(at: record + 6),
                            isExtender: bytes.uint16(at: record + 8) & 1 == 1))
                }
            }
            constructions[glyph] = construction
        }
        return constructions
    }

    /// The glyphs a coverage table lists, in coverage-index order.
    private static func coverage(_ bytes: BigEndianBytes, at start: Int) -> [CGGlyph] {
        let count = Int(bytes.uint16(at: start + 2))
        switch bytes.uint16(at: start) {
        case 1:
            return (0..<count).map { bytes.uint16(at: start + 4 + $0 * 2) }
        case 2:
            return (0..<count).flatMap { range -> [CGGlyph] in
                let record = start + 4 + range * 6
                let first = bytes.uint16(at: record)
                let last = bytes.uint16(at: record + 2)
                return first <= last ? Array(first...last) : []
            }
        default: return []
        }
    }
}

/// Reads past the end as zero, so a truncated table degrades to missing values, never a trap.
private struct BigEndianBytes {
    let bytes: [UInt8]

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    func uint16(at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 1 < bytes.count else { return 0 }
        return UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }

    func int16(at offset: Int) -> Int16 { Int16(bitPattern: uint16(at: offset)) }

    func offset(at position: Int) -> Int { Int(uint16(at: position)) }
}
