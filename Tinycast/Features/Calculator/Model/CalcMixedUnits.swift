import Foundation

/// A quantity told in two units of one kind, the larger whole: `1.75 m to feet and inches`.
enum CalcMixedUnits {
    static func pair(_ target: String) -> (larger: UnitDef, smaller: UnitDef)? {
        let names = target.split(separator: " ").filter { $0 != "and" && $0 != "&" }
        guard names.count == 2, let first = unit(String(names[0])), let second = unit(String(names[1])),
            first.category == second.category, first.factor != second.factor,
            first.category != .temperature, first.category != .compound
        else { return nil }
        return first.factor > second.factor ? (first, second) : (second, first)
    }

    private static func unit(_ name: String) -> UnitDef? {
        CalcUnits.byName[name] ?? CalcUnits.byName[name.lowercased()]
    }

    /// Durations keep whole smaller units, as `timespan` does; anything else keeps its fraction.
    static func format(
        _ amount: Double, from unit: UnitDef, into pair: (larger: UnitDef, smaller: UnitDef)
    ) -> String? {
        let ratio = pair.larger.factor / pair.smaller.factor
        var total = abs(amount) * unit.factor / pair.smaller.factor
        guard total.isFinite else { return nil }
        if unit.category == .time { total.round() }
        var whole = (total / ratio).rounded(.down)
        var remainder = total - whole * ratio
        if remainder < ratio * 1e-10 { remainder = 0 }
        // Display rounding can lift a remainder to a whole larger unit: 11.9999999999 in is a foot.
        if let shown = Double(CalcFormatter.copyText(remainder)), shown >= ratio {
            whole += 1
            remainder = 0
        }
        var parts: [String] = []
        if whole > 0 { parts.append("\(CalcFormatter.display(whole)) \(pair.larger.symbol)") }
        if remainder > 0 || parts.isEmpty {
            parts.append("\(CalcFormatter.display(remainder)) \(pair.smaller.symbol)")
        }
        return (amount < 0 ? "-" : "") + parts.joined(separator: " ")
    }
}
