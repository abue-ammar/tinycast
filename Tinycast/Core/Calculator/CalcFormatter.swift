import Foundation

/// Hand-rolled, locale-independent number formatting (`.` decimal, `,` grouping), deterministic so the test harness can assert exact strings and the palette renders identically across locales.
enum CalcFormatter {
    /// Human-facing: ≤10 significant digits, trailing zeros trimmed, thousands separators.
    static func display(_ value: Double) -> String {
        grouped(copyText(value))
    }

    /// Every integer up to 2^53 is exactly representable as a Double.
    private static let maxExactInteger = 9_007_199_254_740_992.0

    /// Same rounding, no grouping — what lands on the pasteboard.
    static func copyText(_ value: Double) -> String {
        let v = value == 0 ? 0 : value  // normalize -0
        // Past 2^53 the precision is genuinely gone, so exponent form is the honest answer there.
        if v.rounded() == v && abs(v) <= maxExactInteger {
            return String(format: "%.0f", v)
        }
        return String(format: "%.10g", v)
    }

    /// Money rounding for currency answers: two decimals, widening to four significant digits below a cent so a small cross-rate never collapses to "0.00". Deliberately not `%g` — a satoshi-scale rate must read "0.00001551", never "1.551e-05". Ungrouped; the display side wraps this in `grouped`.
    static func currency(_ value: Double) -> String {
        let magnitude = abs(value)
        // Below ~1e-9 even four significant digits are noise. Answering with a literal "0.00" also
        // keeps a tiny negative from printing as "-0.00", which `%.2f` would happily do.
        guard magnitude >= 1e-9 else { return "0.00" }
        guard magnitude < 0.01 else { return String(format: "%.2f", value) }
        var text = String(format: "%.\(3 - Int(floor(log10(magnitude))))f", value)
        while text.hasSuffix("0") { text.removeLast() }
        return text
    }

    /// A length in feet rendered as whole feet + remaining inches ("3 feet 3.370078740 inches"); used only for the bare metric-length auto-conversion. Sub-foot values drop the feet part.
    static func compoundFeetInches(_ feet: Double) -> String {
        let sign = feet < 0 ? "-" : ""
        let magnitude = abs(feet)
        let wholeFeet = magnitude.rounded(.towardZero)
        let inches = (magnitude - wholeFeet) * 12
        let feetPart = wholeFeet == 0 ? "" : "\(sign)\(display(wholeFeet)) \(wholeFeet == 1 ? "foot" : "feet")"
        let inchText = display(inches)
        let inchPart = "\(inchText) \(inchText == "1" ? "inch" : "inches")"
        if feetPart.isEmpty { return "\(sign)\(inchPart)" }
        return "\(feetPart) \(inchPart)"
    }

    /// Insert `,` every three integer digits. Exponent-form strings pass through untouched.
    static func grouped(_ text: String) -> String {
        guard !text.contains("e"), !text.contains("E") else { return text }
        let sign = text.hasPrefix("-") ? "-" : ""
        let unsigned = sign.isEmpty ? text : String(text.dropFirst())
        let parts = unsigned.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let intDigits = Array(parts[0])
        guard intDigits.count > 3 else { return text }

        var groupedInt = ""
        for (i, digit) in intDigits.enumerated() {
            if i > 0 && (intDigits.count - i) % 3 == 0 { groupedInt.append(",") }
            groupedInt.append(digit)
        }
        let fraction = parts.count > 1 ? "." + parts[1] : ""
        return sign + groupedInt + fraction
    }
}
