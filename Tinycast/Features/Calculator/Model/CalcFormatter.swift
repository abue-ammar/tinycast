import Foundation

/// Hand-rolled, locale-independent number formatting, so every locale renders identically.
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

    /// Money: 2 decimals, widening below a cent. Never `%g`. docs/features/calculator.md
    static func currency(_ value: Double) -> String {
        let magnitude = abs(value)
        // Below ~1e-9 the digits are noise, and a literal "0.00" avoids `%.2f`'s "-0.00".
        guard magnitude >= 1e-9 else { return "0.00" }
        guard magnitude < 0.01 else { return String(format: "%.2f", value) }
        var text = String(format: "%.\(3 - Int(floor(log10(magnitude))))f", value)
        while text.hasSuffix("0") { text.removeLast() }
        return text
    }

    /// Whole feet + remaining inches, for the bare metric-length auto-conversion only.
    static func compoundFeetInches(_ feet: Double) -> String {
        let sign = feet < 0 ? "-" : ""
        let magnitude = abs(feet)
        let wholeFeet = magnitude.rounded(.towardZero)
        let inches = (magnitude - wholeFeet) * 12
        let feetPart =
            wholeFeet == 0 ? "" : "\(sign)\(display(wholeFeet)) \(wholeFeet == 1 ? "foot" : "feet")"
        let inchText = display(inches)
        let inchPart = "\(inchText) \(inchText == "1" ? "inch" : "inches")"
        if feetPart.isEmpty { return "\(sign)\(inchPart)" }
        return "\(feetPart) \(inchPart)"
    }

    /// Seconds as the largest units that fit: `8,700` → `2 hr 25 min`.
    static func timespan(_ seconds: Double) -> String {
        guard seconds.isFinite else { return display(seconds) }
        let sign = seconds < 0 ? "-" : ""
        var remainder = abs(seconds).rounded()
        var parts: [String] = []
        for step in timespanSteps where remainder >= step.seconds {
            let count = (remainder / step.seconds).rounded(.towardZero)
            remainder -= count * step.seconds
            parts.append("\(grouped(String(format: "%.0f", count))) \(step.symbol)")
        }
        // Sub-second input has no whole part to show, so it keeps its own precision.
        if parts.isEmpty { return "\(display(seconds)) s" }
        return sign + parts.joined(separator: " ")
    }

    /// Weeks are the largest step: a month is not a fixed number of seconds.
    private static let timespanSteps: [(seconds: Double, symbol: String)] = [
        (604800, "wk"), (86400, "day"), (3600, "hr"), (60, "min"), (1, "s")
    ]

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
