import Foundation

/// Percentage phrasings the arithmetic parser misses: `20% off 500`, `50 as % of 200`.
enum CalcPercent {
    static func evaluate(_ tokens: [CalcToken], query: String) -> CalcResult? {
        parseOff(tokens, query: query) ?? parseAsPercentOf(tokens, query: query)
            ?? parseTip(tokens, query: query) ?? parseWhatPercentOf(tokens, query: query)
            ?? parseIsPercentOfWhat(tokens, query: query) ?? parseRatio(tokens, query: query)
            ?? parseAggregate(tokens, query: query) ?? parseRoundToNearest(tokens, query: query)
    }

    /// `<pct>% off <value>` → the value reduced by pct percent (`20% off 500` → 400).
    private static func parseOff(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard let off = tokens.firstIndex(of: .ident("off")), off >= 2,
            tokens[off - 1] == .op("%"),
            let pct = CalcParser.evaluate(Array(tokens[0..<(off - 1)])),
            let base = CalcParser.evaluate(Array(tokens[(off + 1)...]))
        else { return nil }
        let result = base * (1 - pct / 100)
        guard result.isFinite else { return nil }
        return card(query, CalcFormatter.display(result), CalcFormatter.copyText(result))
    }

    /// `<x> as % of <y>` → x / y × 100, rendered as a percentage (`50 as % of 200` → 25%).
    private static func parseAsPercentOf(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard let asIdx = tokens.firstIndex(of: .ident("as")), asIdx + 2 < tokens.count,
            tokens[asIdx + 1] == .op("%"), tokens[asIdx + 2] == .ident("of"),
            let x = CalcParser.evaluate(Array(tokens[0..<asIdx])),
            let y = CalcParser.evaluate(Array(tokens[(asIdx + 3)...])), y != 0
        else { return nil }
        let ratio = x / y * 100
        guard ratio.isFinite else { return nil }
        return card(query, "\(CalcFormatter.display(ratio))%", "\(CalcFormatter.copyText(ratio))%")
    }

    private static func card(_ query: String, _ display: String, _ copy: String) -> CalcResult {
        CalcResult(
            expression: query.split(whereSeparator: \.isWhitespace).joined(separator: " "),
            sourceBadge: "Expression",
            targetBadge: "Result",
            payload: .value(display: display, copyText: copy))
    }

    /// The tip alone, not the total: it is the number the phrase asks for.
    private static func parseTip(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard let tip = tokens.firstIndex(of: .ident("tip")), tip >= 2,
            tokens[tip - 1] == .op("%"), tip + 1 < tokens.count,
            tokens[tip + 1] == .ident("on") || tokens[tip + 1] == .ident("of"),
            let pct = CalcParser.evaluate(Array(tokens[0..<(tip - 1)])),
            let bill = CalcParser.evaluate(Array(tokens[(tip + 2)...]))
        else { return nil }
        let amount = bill * pct / 100
        guard amount.isFinite else { return nil }
        return card(query, CalcFormatter.display(amount), CalcFormatter.copyText(amount))
    }

    private static func parseWhatPercentOf(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard let isIdx = tokens.firstIndex(of: .ident("is")), isIdx + 3 < tokens.count,
            tokens[isIdx + 1] == .ident("what"), tokens[isIdx + 2] == .op("%"),
            tokens[isIdx + 3] == .ident("of"),
            let x = CalcParser.evaluate(Array(tokens[0..<isIdx])),
            let y = CalcParser.evaluate(Array(tokens[(isIdx + 4)...])), y != 0
        else { return nil }
        let ratio = x / y * 100
        guard ratio.isFinite else { return nil }
        return card(query, "\(CalcFormatter.display(ratio))%", "\(CalcFormatter.copyText(ratio))%")
    }

    private static func parseIsPercentOfWhat(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard tokens.count >= 6, tokens.last == .ident("what"),
            tokens[tokens.count - 2] == .ident("of"), tokens[tokens.count - 3] == .op("%"),
            let isIdx = tokens.firstIndex(of: .ident("is")),
            let x = CalcParser.evaluate(Array(tokens[0..<isIdx])),
            let pct = CalcParser.evaluate(Array(tokens[(isIdx + 1)..<(tokens.count - 3)])),
            pct != 0
        else { return nil }
        let whole = x / (pct / 100)
        guard whole.isFinite else { return nil }
        return card(query, CalcFormatter.display(whole), CalcFormatter.copyText(whole))
    }

    /// Integers only, so the reduced pair stays exact.
    private static func parseRatio(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard tokens.count >= 5, tokens[0] == .ident("ratio"), tokens[1] == .ident("of"),
            let toIdx = tokens.firstIndex(of: .ident("to")),
            let a = CalcParser.evaluate(Array(tokens[2..<toIdx])),
            let b = CalcParser.evaluate(Array(tokens[(toIdx + 1)...])),
            a.rounded() == a, b.rounded() == b, abs(a) <= 1e15, abs(b) <= 1e15, a != 0 || b != 0
        else { return nil }
        let divisor = greatestCommonDivisor(abs(a), abs(b))
        guard divisor > 0 else { return nil }
        let text = "\(CalcFormatter.display(a / divisor)) : \(CalcFormatter.display(b / divisor))"
        return card(query, text, text)
    }

    private static func greatestCommonDivisor(_ a: Double, _ b: Double) -> Double {
        var (x, y) = (a, b)
        while y > 0 { (x, y) = (y, x.truncatingRemainder(dividingBy: y)) }
        return x
    }

    private static func parseAggregate(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard tokens.count >= 3, case .ident(let name) = tokens[0],
            let reduce = aggregates[name], tokens[1] == .ident("of")
        else { return nil }
        let values = splitList(Array(tokens[2...]))
        guard values.count >= 2, let result = reduce(values), result.isFinite else { return nil }
        return card(query, CalcFormatter.display(result), CalcFormatter.copyText(result))
    }

    /// Snaps to a step, not to a digit count, so `nearest 5` means multiples of 5.
    private static func parseRoundToNearest(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard tokens.count >= 5, tokens[0] == .ident("round"),
            let toIdx = tokens.firstIndex(of: .ident("to")), tokens[toIdx + 1] == .ident("nearest"),
            let value = CalcParser.evaluate(Array(tokens[1..<toIdx])),
            let step = CalcParser.evaluate(Array(tokens[(toIdx + 2)...])), step != 0
        else { return nil }
        let result = (value / step).rounded() * step
        guard result.isFinite else { return nil }
        return card(query, CalcFormatter.display(result), CalcFormatter.copyText(result))
    }

    private static let aggregates: [String: @Sendable ([Double]) -> Double?] = [
        "average": { $0.reduce(0, +) / Double($0.count) },
        "avg": { $0.reduce(0, +) / Double($0.count) },
        "mean": { $0.reduce(0, +) / Double($0.count) },
        "sum": { $0.reduce(0, +) },
        "total": { $0.reduce(0, +) },
        "min": { $0.min() }, "max": { $0.max() }
    ]

    /// Each run is evaluated whole, so `sum of 2*3, 4` stays two operands.
    private static func splitList(_ tokens: [CalcToken]) -> [Double] {
        var values: [Double] = []
        var current: [CalcToken] = []
        for token in tokens {
            if token == .comma || token == .ident("and") {
                guard let value = CalcParser.evaluate(current) else { return [] }
                values.append(value)
                current = []
            } else {
                current.append(token)
            }
        }
        guard let last = CalcParser.evaluate(current) else { return [] }
        values.append(last)
        return values
    }
}
