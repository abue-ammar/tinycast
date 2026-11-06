import Foundation

/// Rates spoken over time: `$50/hr for 3 hours`, `download 20 GB at 10 MB/s`, `1 hour at 1.5x`.
enum CalcRatePhrases {
    static func evaluate(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard tokens.contains(where: { keywords.contains($0) }) else { return nil }
        return transfer(tokens, query: query) ?? playback(tokens, query: query)
            ?? perUnit(tokens, query: query) ?? accrued(tokens, query: query)
    }

    private static let keywords: [CalcToken] = [.ident("for"), .ident("at"), .ident("is"), .ident("as")]

    private static func grouped(_ tokens: [CalcToken]) -> [CalcToken] {
        [.op(.open)] + tokens + [.op(.close)]
    }

    private static func isRate(_ value: CalcValue) -> Bool {
        guard case .unit(let unit) = value.kind, let time = unit.dimension?.time else { return false }
        return time < 0
    }

    private static func isDuration(_ value: CalcValue) -> Bool {
        guard case .unit(let unit) = value.kind else { return false }
        return unit.category == .time
    }

    // MARK: - A rate kept up for a while

    /// `$50/hr for 3 hours` and `60 km/h for 30 min` accrue the rate's own numerator.
    private static func accrued(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard let parts = tokens.operands(of: [nil, .ident("for"), nil]),
            let rate = CalcExpressionParser.value(parts[0]), isRate(rate),
            let duration = CalcExpressionParser.value(parts[1]), isDuration(duration),
            let total = CalcExpressionParser.value(grouped(parts[0]) + [.op(.multiply)] + grouped(parts[1]))
        else { return nil }
        return .phrase(
            query, .quantity(total), target: String(localized: "Total"), isCurrency: total.isCurrency)
    }

    // MARK: - Transfers

    private static let transferVerbs: Set<String> = [
        "download", "downloading", "upload", "uploading", "transfer", "transferring", "send", "sending"
    ]

    private static func transfer(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard case .ident(let verb) = tokens.first, transferVerbs.contains(verb),
            let parts = Array(tokens.dropFirst()).operands(of: [nil, .ident("at"), nil]),
            let duration = CalcExpressionParser.value(grouped(parts[0]) + [.op(.divide)] + grouped(parts[1])),
            case .unit(let unit) = duration.kind, unit.category == .time
        else { return nil }
        return durationCard(duration.amount * unit.factor, query: query, badge: String(localized: "Duration"))
    }

    private static func durationCard(_ seconds: Double, query: String, badge: String) -> CalcResult? {
        guard seconds.isFinite, seconds >= 0 else { return nil }
        let text = CalcFormatter.timespan(seconds)
        return .phrase(query, .value(display: text, copyText: text), target: badge)
    }

    // MARK: - Playback speed

    private static func playback(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard let at = tokens.lastIndex(of: .ident("at")), let speed = speedFactor(tokens[(at + 1)...]) else {
            return nil
        }
        var lead = tokens[..<at]
        let saved = lead.starts(with: [.ident("time"), .ident("saved")])
        if saved {
            lead.removeFirst(2)
            if lead.first == .ident("for") || lead.first == .ident("on") { lead.removeFirst() }
        }
        guard var duration = CalcExpressionParser.value(Array(lead)), isDuration(duration) else { return nil }
        duration.amount *= saved ? 1 - 1 / speed : 1 / speed
        let badge = saved ? String(localized: "Time Saved") : String(localized: "Duration")
        return duration.amount.isFinite ? .phrase(query, .quantity(duration), target: badge) : nil
    }

    /// `2x`, `1.5x speed`, `2× speed`: the tokenizer reads a trailing `x` as a word or a product.
    private static func speedFactor(_ tokens: ArraySlice<CalcToken>) -> Double? {
        var rest = Array(tokens)
        if rest.last == .ident("speed") { rest.removeLast() }
        guard rest.count == 2, let factor = rest.first.flatMap(CalcQuantity.numberValue), factor > 0,
            rest[1] == .ident("x") || rest[1] == .op(.multiply)
        else { return nil }
        return factor
    }

    // MARK: - A rate per another unit

    private static func perUnit(_ tokens: [CalcToken], query: String) -> CalcResult? {
        let patterns: [[CalcToken?]] = [
            [nil, .ident("is"), .ident("what"), .op(.divide), nil],
            [nil, .ident("is"), .ident("how"), .ident("much"), .op(.divide), nil],
            [nil, .ident("as"), .op(.divide), nil]
        ]
        guard let parts = patterns.lazy.compactMap({ tokens.operands(of: $0) }).first,
            parts[1].count == 1, case .ident(let name) = parts[1][0],
            let per = CalcUnits.byName[name], per.category == .time,
            let rate = CalcExpressionParser.value(parts[0]), isRate(rate),
            let amount = CalcExpressionParser.value(
                grouped(parts[0]) + [.op(.multiply), .op(.open), .ident(name), .op(.close)]),
            case .value(let display, let copyText) = CalcResult.Payload.quantity(amount)
        else { return nil }
        let suffix = "/" + per.symbol
        return .phrase(
            query, .value(display: display + suffix, copyText: copyText + suffix),
            target: String(localized: "Rate"),
            canChain: false, isCurrency: amount.isCurrency)
    }
}
