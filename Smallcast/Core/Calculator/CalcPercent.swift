import Foundation

/// Natural-language percentage phrasings the arithmetic parser doesn't cover: `20% off 500` (a discount) and `50 as % of 200` (a ratio). Foundation-only so `Tools/calc-test.swift` compiles it with the rest of the engine. `X% of Y` and `Y + X%` already fall out of the `of`/percent operators, so they aren't handled here.
enum CalcPercent {
    static func evaluate(_ tokens: [CalcToken], query: String) -> CalcResult? {
        parseOff(tokens, query: query) ?? parseAsPercentOf(tokens, query: query)
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
}
