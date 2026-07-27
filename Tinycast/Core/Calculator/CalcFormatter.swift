import Foundation

/// Hand-rolled, locale-independent number formatting (`.` decimal, `,` grouping), deterministic so the test harness can assert exact strings and the palette renders identically across locales.
enum CalcFormatter {
    /// Human-facing: ≤10 significant digits, trailing zeros trimmed, thousands separators.
    static func display(_ value: Double) -> String {
        grouped(copyText(value))
    }

    /// Same rounding, no grouping — what lands on the pasteboard.
    static func copyText(_ value: Double) -> String {
        let v = value == 0 ? 0 : value  // normalize -0
        // Integers print in full (not exponent form) while they're exactly representable.
        if v.rounded() == v && abs(v) < 1e15 {
            return String(format: "%.0f", v)
        }
        return String(format: "%.10g", v)
    }

    /// Money rounding for currency answers: two decimals, widening to four significant digits below a cent so a small cross-rate never collapses to "0.00". Deliberately not `%g` — a satoshi-scale rate must read "0.00001551", never "1.551e-05". Ungrouped; the display side wraps this in `grouped`.
    static func currency(_ value: Double) -> String {
        let v = value == 0 ? 0 : value  // normalize -0
        let magnitude = abs(v)
        guard magnitude > 0, magnitude < 0.01 else { return String(format: "%.2f", v) }
        // Below ~1e-9 even four significant digits are noise, so fall back to plain cents.
        let decimals = 3 - Int(floor(log10(magnitude)))
        guard decimals <= 12 else { return String(format: "%.2f", v) }
        var text = String(format: "%.\(decimals)f", v)
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
