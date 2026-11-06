import Foundation

/// Change at a steady rate: `20 after 5 years at 5% every year`, `time from 20 to 30 at 5% every year`.
enum CalcGrowth {
    static func evaluate(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard tokens.contains(.ident("every")) else { return nil }
        return compounded(tokens, query: query) ?? timeToReach(tokens, query: query)
            ?? rateOver(tokens, query: query)
    }

    private typealias Pattern = [CalcToken?]

    private static func word(_ text: String) -> CalcToken { .ident(text) }

    private static let percent = CalcToken.op(.percent)

    private static func grouped(_ tokens: [CalcToken]) -> [CalcToken] {
        [.op(.open)] + tokens + [.op(.close)]
    }

    /// `(a) / (b)` through the typed parser, so `5 years` over `year` cancels to 5.
    private static func ratio(_ a: [CalcToken], _ b: [CalcToken]) -> Double? {
        CalcExpressionParser.scalar(grouped(a) + [.op(.divide)] + grouped(b))
    }

    private static func rate(_ tokens: [CalcToken], trailing: [CalcToken]) -> Double? {
        guard let value = CalcExpressionParser.scalar(tokens) else { return nil }
        let fraction = value / 100
        switch trailing {
        case []: return fraction
        case [word("growth")]: return abs(fraction)
        case [word("decay")]: return -abs(fraction)
        default: return nil
        }
    }

    private static let modifiers: [[CalcToken]] = [[], [word("growth")], [word("decay")]]

    // MARK: - Compounded change

    private static func compounded(_ tokens: [CalcToken], query: String) -> CalcResult? {
        for modifier in modifiers {
            let pattern: Pattern =
                [nil, word("after"), nil, word("at"), nil, percent] + modifier + [word("every"), nil]
            guard let parts = tokens.operands(of: pattern), var start = CalcExpressionParser.value(parts[0]),
                !start.isPercent, let perPeriod = rate(parts[2], trailing: modifier),
                let periods = ratio(parts[1], parts[3]), periods >= 0
            else { continue }
            start.amount *= pow(1 + perPeriod, periods)
            guard start.amount.isFinite else { return nil }
            return .phrase(
                query, .quantity(start), target: String(localized: "Future Value"),
                isCurrency: start.isCurrency)
        }
        return nil
    }

    // MARK: - Time to reach a value

    private static func timeToReach(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard case .ident(let lead) = tokens.first, tokens.count > 1, tokens[1] == word("from") else {
            return nil
        }
        let unit = CalcUnits.byName[lead]
        guard lead == "time" || unit?.category == .time else { return nil }
        let rest = Array(tokens.dropFirst(2))
        guard let (periods, period) = compoundedPeriods(rest) ?? linearPeriods(rest), periods.isFinite,
            periods >= 0, var duration = CalcExpressionParser.value(grouped(period)),
            case .unit(let periodUnit) = duration.kind, periodUnit.category == .time
        else { return nil }
        duration.amount *= periods
        if let unit, unit !== periodUnit {
            duration = CalcValue(
                amount: CalcQuantity.convertUnit(duration.amount, from: periodUnit, to: unit),
                kind: .unit(unit))
        }
        return .phrase(query, .quantity(duration), target: String(localized: "Duration"))
    }

    private static func compoundedPeriods(_ tokens: [CalcToken]) -> (Double, [CalcToken])? {
        for modifier in modifiers {
            let pattern: Pattern =
                [nil, word("to"), nil, word("at"), nil, percent] + modifier + [word("every"), nil]
            guard let parts = tokens.operands(of: pattern),
                let perPeriod = rate(parts[2], trailing: modifier),
                perPeriod > -1, perPeriod != 0, let growth = ratio(parts[1], parts[0]), growth > 0
            else { continue }
            return (log(growth) / log(1 + perPeriod), parts[3])
        }
        return nil
    }

    private static func linearPeriods(_ tokens: [CalcToken]) -> (Double, [CalcToken])? {
        guard let parts = tokens.operands(of: [nil, word("to"), nil, word("at"), nil, word("every"), nil]),
            let steps = ratio(grouped(parts[1]) + [.op(.subtract)] + grouped(parts[0]), parts[2])
        else { return nil }
        return (steps, parts[3])
    }

    // MARK: - The rate that explains a change

    private static func rateOver(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard case .ident(let lead) = tokens.first, lead == "growth" || lead == "decay",
            let parts = tokens.operands(
                of: [word(lead), word("every"), nil, word("from"), nil, word("to"), nil, word("over"), nil]),
            let change = ratio(parts[2], parts[1]), change > 0, let periods = ratio(parts[3], parts[0]),
            periods > 0
        else { return nil }
        let perPeriod = pow(change, 1 / periods) - 1
        let value = (lead == "decay" ? -perPeriod : perPeriod) * 100
        guard value.isFinite else { return nil }
        return .phrase(query, .number(value, suffix: "%"), target: String(localized: "Growth Rate"))
    }
}
