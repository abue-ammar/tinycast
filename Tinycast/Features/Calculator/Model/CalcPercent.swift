import Foundation

/// Percentage phrasings the arithmetic parser misses: `20% off 500`, `50 as % of 200`.
enum CalcPercent {
    static func evaluate(_ tokens: [CalcToken], query: String) -> CalcResult? {
        if let adjusted = adjusted(tokens) {
            return .phrase(
                query, .quantity(adjusted.value), target: adjusted.badge,
                isCurrency: adjusted.value.isCurrency)
        }
        if let percentage = percentage(tokens) {
            return .phrase(query, .number(percentage.value, suffix: "%"), target: percentage.badge)
        }
        return parseRatio(tokens, query: query) ?? parseAggregate(tokens, query: query)
    }

    /// A discount, tip or markup phrase's amount, unrounded, for a caller that shares it out.
    static func amount(_ tokens: [CalcToken]) -> CalcValue? {
        adjusted(tokens)?.value
    }

    // MARK: - Phrase patterns

    private typealias Pattern = [CalcToken?]

    private static let percent = CalcToken.op(.percent)

    private static func word(_ text: String) -> CalcToken { .ident(text) }

    // MARK: - Amounts scaled by a percentage

    /// The operand that keeps its unit, and the multiplier the percentage operand makes of it.
    private struct Adjustment {
        let pattern: Pattern
        let badge: String
        let amountIndex: Int
        let factor: @Sendable (Double) -> Double
    }

    private static let adjustments: [Adjustment] = [
        Adjustment(
            pattern: [nil, percent, word("tip"), word("on"), nil], badge: String(localized: "Tip"),
            amountIndex: 1, factor: { $0 / 100 }),
        Adjustment(
            pattern: [nil, percent, word("tip"), word("of"), nil], badge: String(localized: "Tip"),
            amountIndex: 1, factor: { $0 / 100 }),
        Adjustment(
            pattern: [nil, percent, word("off"), nil], badge: String(localized: "Discounted"),
            amountIndex: 1, factor: { 1 - $0 / 100 }),
        Adjustment(
            pattern: [nil, percent, word("on"), nil], badge: String(localized: "Increased"),
            amountIndex: 1, factor: { 1 + $0 / 100 }),
        Adjustment(
            pattern: [nil, word("is"), nil, percent, word("of"), word("what")],
            badge: String(localized: "Total"),
            amountIndex: 0, factor: { 100 / $0 }),
        Adjustment(
            pattern: [nil, word("is"), nil, percent, word("off"), word("what")],
            badge: String(localized: "Total"),
            amountIndex: 0, factor: { 1 / (1 - $0 / 100) }),
        Adjustment(
            pattern: [nil, word("is"), nil, percent, word("on"), word("what")],
            badge: String(localized: "Total"),
            amountIndex: 0, factor: { 1 / (1 + $0 / 100) })
    ]

    private static func adjusted(_ tokens: [CalcToken]) -> (value: CalcValue, badge: String)? {
        for adjustment in adjustments {
            guard let parts = tokens.operands(of: adjustment.pattern),
                var amount = CalcExpressionParser.value(parts[adjustment.amountIndex]), !amount.isPercent,
                let percentage = CalcExpressionParser.scalar(parts[1 - adjustment.amountIndex])
            else { continue }
            amount.amount *= adjustment.factor(percentage)
            return amount.amount.isFinite ? (amount, adjustment.badge) : nil
        }
        return nil
    }

    // MARK: - Percentages of, between and as

    private struct Ratio {
        let pattern: Pattern
        let badge: String
        let percentage: @Sendable ([[CalcToken]]) -> Double?
    }

    private static let ratios: [Ratio] = [
        Ratio(
            pattern: [nil, word("as"), percent, word("of"), nil], badge: String(localized: "Percentage"),
            percentage: { share($0[0], of: $0[1]) }),
        Ratio(
            pattern: [nil, word("as"), word("a"), percent, word("of"), nil],
            badge: String(localized: "Percentage"),
            percentage: { share($0[0], of: $0[1]) }),
        Ratio(
            pattern: [nil, word("is"), word("what"), percent, word("of"), nil],
            badge: String(localized: "Percentage"), percentage: { share($0[0], of: $0[1]) }),
        Ratio(
            pattern: [nil, word("is"), word("what"), percent, word("off"), nil],
            badge: String(localized: "Percent Change"),
            percentage: { share($0[0], of: $0[1]).map { 100 - $0 } }),
        Ratio(
            pattern: [nil, word("is"), word("what"), percent, word("on"), nil],
            badge: String(localized: "Percent Change"),
            percentage: { share($0[0], of: $0[1]).map { $0 - 100 } }),
        Ratio(
            pattern: [nil, word("to"), nil, word("is"), word("what"), percent],
            badge: String(localized: "Percent Change"),
            percentage: { share($0[1], of: $0[0]).map { $0 - 100 } }),
        Ratio(
            pattern: [nil, word("to"), nil, word("as"), percent], badge: String(localized: "Percent Change"),
            percentage: { share($0[1], of: $0[0]).map { $0 - 100 } }),
        Ratio(
            pattern: [nil, word("as"), percent], badge: String(localized: "Percentage"),
            percentage: { CalcExpressionParser.scalar($0[0]).map { $0 * 100 } }),
        Ratio(
            pattern: [nil, word("as"), word("percent")], badge: String(localized: "Percentage"),
            percentage: { CalcExpressionParser.scalar($0[0]).map { $0 * 100 } }),
        Ratio(
            pattern: [nil, word("is"), word("what"), percent], badge: String(localized: "Percentage"),
            percentage: { CalcExpressionParser.scalar($0[0]).map { $0 * 100 } })
    ]

    private static func percentage(_ tokens: [CalcToken]) -> (value: Double, badge: String)? {
        for ratio in ratios {
            guard let parts = tokens.operands(of: ratio.pattern), let value = ratio.percentage(parts),
                value.isFinite
            else { continue }
            return (value, ratio.badge)
        }
        return nil
    }

    /// As a percentage, divided by the parser so compatible units cancel: `500 m as % of 2 km` is 25%.
    private static func share(_ part: [CalcToken], of whole: [CalcToken]) -> Double? {
        let quotient = [.op(.open)] + part + [.op(.close), .op(.divide), .op(.open)] + whole + [.op(.close)]
        return CalcExpressionParser.scalar(quotient).map { $0 * 100 }
    }

    // MARK: - Ratios and lists

    /// Integers only, so the reduced pair stays exact.
    private static func parseRatio(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard tokens.count >= 5, tokens[0] == .ident("ratio"), tokens[1] == .ident("of"),
            let toIdx = tokens.firstIndex(of: .ident("to")),
            let a = CalcExpressionParser.scalar(Array(tokens[2..<toIdx])),
            let b = CalcExpressionParser.scalar(Array(tokens[(toIdx + 1)...])),
            a.rounded() == a, b.rounded() == b, abs(a) <= 1e15, abs(b) <= 1e15, a != 0 || b != 0
        else { return nil }
        let divisor = greatestCommonDivisor(abs(a), abs(b))
        guard divisor > 0 else { return nil }
        let text = "\(CalcFormatter.display(a / divisor)) : \(CalcFormatter.display(b / divisor))"
        return .phrase(
            query, .value(display: text, copyText: text), target: String(localized: "Ratio"),
            canChain: false)
    }

    private static func greatestCommonDivisor(_ a: Double, _ b: Double) -> Double {
        var (x, y) = (a, b)
        while y > 0 { (x, y) = (y, x.truncatingRemainder(dividingBy: y)) }
        return x
    }

    private static func parseAggregate(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard tokens.count >= 3, case .ident(let name) = tokens[0], let aggregate = aggregates[name],
            tokens[1] == .ident(aggregate.joiner)
        else { return nil }
        let values = splitList(Array(tokens[2...]))
        guard values.count >= 2, let result = aggregate.reduce(values), result.isFinite
        else { return nil }
        return .phrase(query, .number(result), target: aggregate.name)
    }

    /// The badge names which reduction ran, so `min` and `max` are told apart on the card.
    private struct Aggregate {
        let name: String
        var joiner = "of"
        let reduce: @Sendable ([Double]) -> Double?
    }

    private static let aggregates: [String: Aggregate] = {
        let average = Aggregate(name: String(localized: "Average")) { $0.reduce(0, +) / Double($0.count) }
        let sum = Aggregate(name: String(localized: "Sum")) { $0.reduce(0, +) }
        let minimum = Aggregate(name: String(localized: "Minimum")) { $0.min() }
        let maximum = Aggregate(name: String(localized: "Maximum")) { $0.max() }
        return [
            "average": average, "avg": average, "mean": average,
            "midpoint": Aggregate(name: average.name, joiner: "between", reduce: average.reduce),
            "sum": sum, "total": sum,
            "min": minimum, "smaller": minimum, "lesser": minimum,
            "max": maximum, "larger": maximum, "greater": maximum,
            "gcd": Aggregate(name: String(localized: "Result")) { CalcMath.evaluate("gcd", $0) },
            "lcm": Aggregate(name: String(localized: "Result")) { CalcMath.evaluate("lcm", $0) }
        ]
    }()

    /// Each run is evaluated whole, so `sum of 2*3, 4` stays two operands.
    private static func splitList(_ tokens: [CalcToken]) -> [Double] {
        var values: [Double] = []
        var current: [CalcToken] = []
        for token in tokens {
            if token == .comma || token == .ident("and") {
                guard let value = CalcExpressionParser.scalar(current) else { return [] }
                values.append(value)
                current = []
            } else {
                current.append(token)
            }
        }
        guard let last = CalcExpressionParser.scalar(current) else { return [] }
        values.append(last)
        return values
    }
}
