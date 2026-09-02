import Foundation

/// The notations a parsed colour can be rewritten as. See docs/features/clipboard.md#colours.
enum ColorFormat: CaseIterable, Hashable, Sendable {
    case hex
    case hexWithAlpha
    case rgba
    case hsl
    case hslWithAlpha
    case oklch

    /// The menu row's label; the rendered value is its trailing text.
    var title: String {
        switch self {
        case .hex: return "Hex"
        case .hexWithAlpha: return "Hex with Alpha"
        case .rgba: return "RGBA"
        case .hsl: return "HSL"
        case .hslWithAlpha: return "HSL with Alpha"
        case .oklch: return "Oklch"
        }
    }

    /// What the colour reads as in this notation.
    func string(for color: ColorValue) -> String {
        switch self {
        case .hex: return ColorDigits.hex(color, includingAlpha: false)
        case .hexWithAlpha: return ColorDigits.hex(color, includingAlpha: true)
        case .rgba:
            return "rgba(\(ColorDigits.channel(color.red)), \(ColorDigits.channel(color.green)), "
                + "\(ColorDigits.channel(color.blue)), \(ColorDigits.decimal(color.alpha)))"
        case .hsl, .hslWithAlpha:
            let hsl = color.hsl
            let alpha = carriesAlpha ? ", \(ColorDigits.decimal(color.alpha))" : ""
            return "hsl(\(ColorDigits.angle(hsl.hue)), \(ColorDigits.percent(hsl.saturation)), "
                + "\(ColorDigits.percent(hsl.lightness))\(alpha))"
        case .oklch:
            let oklch = color.oklch
            // Oklab's axes run to about ±0.4, so a tenth would state most colours as zero.
            return "oklch(\(ColorDigits.percent(oklch.l)) \(ColorDigits.decimal(oklch.c)) "
                + "\(ColorDigits.angle(oklch.h))\(ColorDigits.slashAlpha(color)))"
        }
    }

    /// An alpha-bearing row only where there is alpha, so no opaque duplicate is ever offered.
    static func offered(for color: ColorValue) -> [ColorFormat] {
        allCases.filter { color.hasAlpha || !$0.carriesAlpha }
    }

    /// What the card states and ↵ copies: the shortest notation that keeps the colour whole.
    static func primary(for color: ColorValue) -> ColorFormat {
        color.hasAlpha ? .hexWithAlpha : .hex
    }

    private var carriesAlpha: Bool {
        switch self {
        // The CSS4 spellings state alpha only when there is any, so they are never duplicates.
        case .hexWithAlpha, .hslWithAlpha: return true
        default: return false
        }
    }
}

/// The digits a notation is spelled in — private, because writing a colour is this file's business.
private enum ColorDigits {
    /// Uppercase, the spelling a hex colour is conventionally written in.
    static func hex(_ color: ColorValue, includingAlpha: Bool) -> String {
        let channels = [color.red, color.green, color.blue] + (includingAlpha ? [color.alpha] : [])
        return "#" + channels.map { String(format: "%02X", channel($0)) }.joined()
    }

    /// One 0…255 channel, rounded the way every 8-bit notation states it.
    static func channel(_ value: Double) -> Int { integer(value * 255) }

    /// Trailing zeros dropped, so an exact channel reads `1` rather than `1.000`.
    static func decimal(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        let rounded = (value * 1000).rounded() / 1000
        return rounded == rounded.rounded()
            ? String(integer(rounded)) : String(format: "%g", rounded)
    }

    /// One decimal, dropped when exact: whole percents cost up to 5/255 on the way back.
    static func percent(_ value: Double) -> String { number(value * 100) + "%" }

    /// An angle carries its unit, the way CSS Color 4 writes every hue.
    static func angle(_ value: Double) -> String { number(value) + "deg" }

    /// `oklch()` states alpha behind a slash, and says nothing where a colour is opaque.
    static func slashAlpha(_ color: ColorValue) -> String {
        color.hasAlpha ? " / " + decimal(color.alpha) : ""
    }

    private static func number(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        let tenths = (value * 10).rounded() / 10
        return tenths == tenths.rounded() ? String(integer(tenths)) : String(format: "%.1f", tenths)
    }

    /// One funnel, because `Int(_:)` traps on a non-finite Double and every notation ends in one.
    private static func integer(_ value: Double) -> Int {
        value.isFinite ? Int(value.rounded()) : 0
    }
}
