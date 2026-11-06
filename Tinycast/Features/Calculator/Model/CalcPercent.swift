import Foundation

/// Percentage phrasings the arithmetic parser misses: `20% off 500`, `50 as % of 200`.
enum CalcPercent {
    static func evaluate(_ tokens: [CalcToken], query: String) -> CalcResult? {
        let tokens = withoutComment(tokens)
        if let adjusted = adjusted(tokens) ?? ruleOfThreeAmount(tokens) ?? withTax(tokens) {
            return .phrase(
                query, .quantity(adjusted.value), target: adjusted.badge,
                isCurrency: adjusted.value.isCurrency)
        }
        if let percentage = percentage(tokens) ?? ruleOfThreePercentage(tokens) {
            return .phrase(query, .number(percentage.value, suffix: "%"), target: percentage.badge)
        }
        return parseRatio(tokens, query: query)
    }

    /// A discount, tip or markup phrase's amount, unrounded, for a caller that shares it out.
    static func amount(_ tokens: [CalcToken]) -> CalcValue? {
        adjusted(withoutComment(tokens))?.value
    }

    // MARK: - Comment words

    /// Words that name a percentage without changing it: `20% discount off 100` is `20% off 100`.
    private static func withoutComment(_ tokens: [CalcToken]) -> [CalcToken] {
        var tokens = tokens
        if let sales = tokens.firstIndex(of: word("sales")), sales + 1 < tokens.count,
            tokens[sales + 1] == word("tax")
        {
            tokens.remove(at: sales)
        }
        guard let index = tokens.firstIndex(of: percent), index + 2 < tokens.count,
            case .ident(let name) = tokens[index + 1], !keptWords.contains(name),
            CalcUnits.byName[name] == nil, CalcCurrency.byName[name] == nil
        else { return tokens }
        let relation = tokens[index + 2]
        let namesIncludedTax = taxWords.contains(name) && relation == word("in")
        guard !namesIncludedTax, [word("of"), word("on"), word("off"), word("in")].contains(relation) else {
            return tokens
        }
        tokens.remove(at: index + 1)
        return tokens
    }

    /// Words with a meaning of their own: a tip is the tip alone, and tax `in` a price is inside it.
    private static let keptWords: Set<String> = [
        "tip", "of", "on", "off", "is", "what", "with", "change", "increase", "decrease", "after"
    ]

    private static let taxWords: Set<String> = ["tax", "vat", "gst"]

    private static func withTax(_ tokens: [CalcToken]) -> (value: CalcValue, badge: String)? {
        guard tokens.count >= 4, case .ident(let name) = tokens.last, taxWords.contains(name),
            tokens[tokens.count - 2] == percent,
            let value = CalcExpressionParser.value(Array(tokens.dropLast())), !value.isPercent
        else { return nil }
        return (value, String(localized: "Total"))
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

    private static let adjustments: [Adjustment] =
        [
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
                pattern: [nil, percent, word("off"), word("of"), nil], badge: String(localized: "Discounted"),
                amountIndex: 1, factor: { 1 - $0 / 100 }),
            Adjustment(
                pattern: [word("take"), nil, percent, word("off"), nil],
                badge: String(localized: "Discounted"),
                amountIndex: 1, factor: { 1 - $0 / 100 }),
            Adjustment(
                pattern: [nil, percent, word("of"), nil], badge: String(localized: "Result"),
                amountIndex: 1, factor: { $0 / 100 }),
            Adjustment(
                pattern: [nil, percent, word("from"), nil], badge: String(localized: "Result"),
                amountIndex: 1, factor: { $0 / 100 }),
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
                amountIndex: 0, factor: { 1 / (1 + $0 / 100) }),
            Adjustment(
                pattern: [nil, percent, word("of"), word("what"), word("is"), nil],
                badge: String(localized: "Total"),
                amountIndex: 1, factor: { 100 / $0 }),
            Adjustment(
                pattern: [nil, percent, word("off"), word("what"), word("is"), nil],
                badge: String(localized: "Total"),
                amountIndex: 1, factor: { 1 / (1 - $0 / 100) }),
            Adjustment(
                pattern: [nil, percent, word("on"), word("what"), word("is"), nil],
                badge: String(localized: "Total"),
                amountIndex: 1, factor: { 1 / (1 + $0 / 100) })
        ]

    /// The tax already inside a price: `20% vat in 120` is 20.
    private static let includedTax: [Adjustment] = taxWords.map { name in
        Adjustment(
            pattern: [nil, percent, word(name), word("in"), nil], badge: String(localized: "Tax"),
            amountIndex: 1, factor: { $0 / (100 + $0) })
    }

    private static func adjusted(_ tokens: [CalcToken]) -> (value: CalcValue, badge: String)? {
        for adjustment in [adjustments, includedTax].joined() {
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
            pattern: [word("what"), percent, word("is"), nil, word("of"), nil],
            badge: String(localized: "Percentage"), percentage: { share($0[0], of: $0[1]) }),
        Ratio(
            pattern: [nil, word("is"), percent, word("of"), nil], badge: String(localized: "Percentage"),
            percentage: { share($0[0], of: $0[1]) }),
        Ratio(
            pattern: [nil, word("is"), word("what"), percent, nil], badge: String(localized: "Percentage"),
            percentage: { share($0[0], of: $0[1]) }),
        Ratio(
            pattern: [nil, word("as"), percent, nil], badge: String(localized: "Percentage"),
            percentage: { share($0[0], of: $0[1]) }),
        Ratio(
            pattern: [nil, word("is"), word("what"), percent, word("with"), nil],
            badge: String(localized: "Percentage"), percentage: { share($0[0], with: $0[1]) }),
        Ratio(
            pattern: [nil, word("as"), percent, word("with"), nil], badge: String(localized: "Percentage"),
            percentage: { share($0[0], with: $0[1]) }),
        Ratio(
            pattern: [nil, word("out"), word("of"), nil], badge: String(localized: "Percentage"),
            percentage: { share($0[0], of: $0[1]) }),
        Ratio(
            pattern: [nil, word("as"), word("discount"), word("off"), nil],
            badge: String(localized: "Percent Change"),
            percentage: { share($0[0], of: $0[1]).map { 100 - $0 } }),
        Ratio(
            pattern: [nil, word("is"), word("what"), word("discount"), word("off"), nil],
            badge: String(localized: "Percent Change"),
            percentage: { share($0[0], of: $0[1]).map { 100 - $0 } }),
        Ratio(
            pattern: [percent, word("change"), word("from"), nil, word("to"), nil],
            badge: String(localized: "Percent Change"),
            percentage: { share($0[1], of: $0[0]).map { $0 - 100 } }),
        Ratio(
            pattern: [percent, word("increase"), word("from"), nil, word("to"), nil],
            badge: String(localized: "Percent Change"),
            percentage: { share($0[1], of: $0[0]).map { $0 - 100 } }),
        Ratio(
            pattern: [percent, word("decrease"), word("from"), nil, word("to"), nil],
            badge: String(localized: "Percent Change"),
            percentage: { share($0[1], of: $0[0]).map { $0 - 100 } }),
        Ratio(
            pattern: [word("what"), percent, word("change"), word("is"), nil, word("to"), nil],
            badge: String(localized: "Percent Change"),
            percentage: { share($0[1], of: $0[0]).map { $0 - 100 } }),
        Ratio(
            pattern: [nil, word("as"), percent, word("after"), word("adding"), nil],
            badge: String(localized: "Percent Change"), percentage: { growth($0[0], after: $0[1]) }),
        Ratio(
            pattern: [nil, word("as"), percent, word("after"), nil],
            badge: String(localized: "Percent Change"), percentage: { growth($0[0], after: $0[1]) }),
        Ratio(
            pattern: [nil, word("is"), word("what"), percent, word("after"), word("adding"), nil],
            badge: String(localized: "Percent Change"), percentage: { growth($0[0], after: $0[1]) }),
        Ratio(
            pattern: [nil, word("is"), word("what"), percent, word("after"), nil],
            badge: String(localized: "Percent Change"), percentage: { growth($0[0], after: $0[1]) }),
        Ratio(
            pattern: [nil, word("as"), percent], badge: String(localized: "Percentage"),
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

    /// One part's share of the whole the two make together: `10 is what % with 20` is a third.
    private static func share(_ part: [CalcToken], with other: [CalcToken]) -> Double? {
        share(part, of: [.op(.open)] + part + [.op(.close), .op(.add), .op(.open)] + other + [.op(.close)])
    }

    /// What adding `delta` grew by, given the total it reached: `15 as % after adding 3` is 25%.
    private static func growth(_ total: [CalcToken], after delta: [CalcToken]) -> Double? {
        let base = [.op(.open)] + total + [.op(.close), .op(.subtract), .op(.open)] + delta + [.op(.close)]
        return share(delta, of: base)
    }

    // MARK: - Rule of three

    private static func ruleOfThreeAmount(_ tokens: [CalcToken]) -> (value: CalcValue, badge: String)? {
        let words = ruleOfThreeWords(tokens)
        guard let (known, knownPercent, askedPercent) = ruleOfThreeParts(words, askedIsPercent: true),
            var value = CalcExpressionParser.value(known), !value.isPercent,
            let given = CalcExpressionParser.scalar(knownPercent), given != 0,
            let asked = CalcExpressionParser.scalar(askedPercent)
        else { return nil }
        value.amount *= asked / given
        return value.amount.isFinite ? (value, String(localized: "Proportion")) : nil
    }

    private static func ruleOfThreePercentage(_ tokens: [CalcToken]) -> (value: Double, badge: String)? {
        let words = ruleOfThreeWords(tokens)
        guard let (known, knownPercent, asked) = ruleOfThreeParts(words, askedIsPercent: false),
            let ratio = share(asked, of: known), let given = CalcExpressionParser.scalar(knownPercent)
        else { return nil }
        let value = ratio / 100 * given
        return value.isFinite ? (value, String(localized: "Percentage")) : nil
    }

    private static func ruleOfThreeWords(_ tokens: [CalcToken]) -> [CalcToken] {
        let rest = tokens.first == word("if") ? Array(tokens.dropFirst()) : tokens
        return rest.filter { $0 != .comma }
    }

    /// The known amount, its percentage, and what is asked, in either `30 is 20%` or `20% is 30` order.
    private static func ruleOfThreeParts(
        _ tokens: [CalcToken], askedIsPercent: Bool
    ) -> ([CalcToken], [CalcToken], [CalcToken])? {
        let ask: Pattern =
            askedIsPercent ? [word("what"), word("is"), nil, percent] : [word("what"), word("is"), nil]
        if let parts = tokens.operands(of: [nil, word("is"), nil, percent] + ask) {
            return (parts[0], parts[1], parts[2])
        }
        if let parts = tokens.operands(of: [nil, percent, word("is"), nil] + ask) {
            return (parts[1], parts[0], parts[2])
        }
        return nil
    }

    /// As a percentage, divided by the parser so compatible units cancel: `500 m as % of 2 km` is 25%.
    private static func share(_ part: [CalcToken], of whole: [CalcToken]) -> Double? {
        let quotient = [.op(.open)] + part + [.op(.close), .op(.divide), .op(.open)] + whole + [.op(.close)]
        return CalcExpressionParser.scalar(quotient).map { $0 * 100 }
    }

    // MARK: - Ratios

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
}
