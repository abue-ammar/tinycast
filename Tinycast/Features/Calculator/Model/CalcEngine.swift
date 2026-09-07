import Foundation

/// A single evaluated calculator answer for the launcher's inline card.
struct CalcResult: Equatable, Sendable {
    enum Payload: Equatable, Sendable {
        /// `display` is grouped ("1,234,567"); `copyText` is the same answer, ungrouped.
        case value(display: String, copyText: String)
        /// A friendly error, only for a clear conversion attempt — never a half-typed expression.
        case error(message: String)

        static func number(_ value: Double, suffix: String = "") -> Self {
            let text = CalcFormatter.copyText(value)
            return .value(display: CalcFormatter.grouped(text) + suffix, copyText: text + suffix)
        }
    }

    /// Normalized echo of what was evaluated, shown on the card's left side ("3×3", "10 km").
    let expression: String
    /// Optional word-name pills beneath each side; nil for plain arithmetic.
    let sourceBadge: String?
    let targetBadge: String?
    let payload: Payload

    init(expression: String, sourceBadge: String? = nil, targetBadge: String? = nil, payload: Payload) {
        self.expression = expression
        self.sourceBadge = sourceBadge
        self.targetBadge = targetBadge
        self.payload = payload
    }

    /// True only for a copyable value; an error card has no primary action and no actions menu.
    var isActionable: Bool {
        if case .value = payload { return true }
        return false
    }
}

/// Raw query to answer, or nil when it isn't calculator input. See docs/features/calculator.md.
enum CalcEngine {
    /// `now`/`calendar`/`region` are injected so every path is deterministic under the harness.
    static func evaluate(
        _ raw: String, now: Date, calendar: Calendar, rates: CurrencyRates? = nil,
        region: String? = nil
    ) -> CalcResult? {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 256 else { return nil }
        guard !query.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) }) else { return nil }

        if let dateTime = CalcDateTime.evaluate(query, now: now, calendar: calendar) { return dateTime }

        // Before tokenizing: `5pm ldn in sf` is words, which the tokenizer would reject.
        if let zone = CalcTimeZone.evaluate(query, now: now, calendar: calendar) { return zone }

        guard let tokens = CalcTokenizer.tokenize(query), !tokens.isEmpty else { return nil }

        if let partial = partialResult(
            tokens, query: query, now: now, calendar: calendar, rates: rates, region: region)
        {
            return partial
        }

        // A lone literal reads as an app search, so no card — except a radix one ("0xff").
        if tokens.count == 1 {
            if case .intLiteral(let value, let base) = tokens[0], base != .decimal {
                let display = CalcFormatter.grouped(String(value))
                return CalcResult(
                    expression: query,
                    sourceBadge: base.name, targetBadge: "Decimal",
                    payload: .value(display: display, copyText: String(value)))
            }
            if case .compactNumber(let value) = tokens[0] {
                return CalcResult(
                    expression: query,
                    sourceBadge: "Expression", targetBadge: "Result",
                    payload: .number(value))
            }
            return nil
        }

        if let base = baseConversion(tokens, query: query) { return base }

        // Typed arithmetic first, so aliases such as `pounds` keep winning in multi-term exprs.
        if let quantity = CalcQuantity.evaluate(tokens, query: query, rates: rates, region: region) {
            return quantity
        }

        // Conversions run before the numeric reject below: `m to ft`, `day s` carry no digit.
        if let conversion = CalcUnits.parseConversion(tokens) ?? CalcUnits.parseUnitPairConversion(tokens) {
            switch conversion {
            case .value(let input, let from, let to, let output):
                return CalcResult(
                    expression: "\(CalcFormatter.display(input)) \(from.symbol)",
                    sourceBadge: from.name,
                    targetBadge: to.name,
                    payload: .number(output, suffix: " \(to.symbol)"))
            case .mismatch(let from, let to):
                return CalcResult(
                    expression: query,
                    payload: .error(
                        message:
                            "Cannot convert \(from.category.displayName) to \(to.category.displayName)."
                    ))
            }
        }

        // After units, so `10 pounds to kg` stays weight.
        if let conversion = CalcCurrency.parseConversion(tokens, rates: rates) {
            switch conversion {
            case .value(let input, let from, let to, let output):
                let amount = CalcFormatter.currency(output)
                return CalcResult(
                    expression: "\(CalcFormatter.display(input)) \(from.code)",
                    sourceBadge: from.name,
                    targetBadge: to.name,
                    payload: .value(
                        display: "\(CalcFormatter.grouped(amount)) \(to.code)",
                        copyText: "\(amount) \(to.code)"))
            case .mismatch(let from, let to):
                return CalcResult(
                    expression: query,
                    payload: .error(message: "Cannot convert \(from) to \(to)."))
            case .noRate(let code):
                return CalcResult(
                    expression: query,
                    payload: .error(message: "No exchange rate for \(code)."))
            case .unavailable:
                return CalcResult(
                    expression: query,
                    payload: .error(message: "Exchange rates unavailable — check your connection."))
            }
        }

        // Keyword-less conversion: `1m` → feet+inches, `1hr` → 60 min.
        if let bare = CalcUnits.parseBareConversion(tokens) {
            let payload: CalcResult.Payload
            if bare.compound {
                let text = CalcFormatter.compoundFeetInches(bare.output)
                payload = .value(display: text, copyText: text)
            } else {
                payload = .number(bare.output, suffix: " \(bare.to.symbol)")
            }
            return CalcResult(
                expression: "\(CalcFormatter.display(bare.input)) \(bare.from.symbol)",
                sourceBadge: bare.from.name,
                targetBadge: bare.to.name,
                payload: payload)
        }

        // Natural-language percent: `20% off 500`, `50 as % of 200`.
        if let percent = CalcPercent.evaluate(tokens, query: query) { return percent }

        return nil
    }

    // MARK: - Partial expressions

    /// A trailing operator keeps the last complete prefix on the card while the user still types.
    private static func partialResult(
        _ tokens: [CalcToken], query: String, now: Date, calendar: Calendar,
        rates: CurrencyRates?, region: String?
    ) -> CalcResult? {
        guard let trailing = tokens.last, let operatorText = partialOperatorText(trailing) else {
            return nil
        }
        let prefixTokens = Array(tokens.dropLast())
        guard !prefixTokens.isEmpty else { return nil }
        if prefixTokens.count == 1, let value = decimalLiteral(prefixTokens[0]) {
            return CalcResult(expression: CalcFormatter.expression(query),
                sourceBadge: "Expression", targetBadge: "Result", payload: .number(value))
        }

        if let quantity = CalcQuantity.evaluate(
            prefixTokens, query: tokenQuery(prefixTokens), rates: rates, region: region,
            preserveStandaloneUnit: true)
        {
            return replacingExpression(
                quantity, with: "\(quantity.expression) \(operatorText)")
        }

        // A conversion's echo drops its target, so echo the typed text; the badges name both.
        if let complete = evaluate(
            tokenQuery(prefixTokens), now: now, calendar: calendar, rates: rates, region: region)
        {
            return replacingExpression(complete, with: CalcFormatter.expression(query))
        }

        guard let value = CalcExpressionParser.scalar(prefixTokens) else { return nil }
        return CalcResult(
            expression: CalcFormatter.expression(query),
            sourceBadge: "Expression", targetBadge: "Result",
            payload: .number(value))
    }

    private static func partialOperatorText(_ token: CalcToken) -> String? {
        guard case .op(let op) = token else { return nil }
        switch op {
        case .multiply: return "×"
        case .divide: return "÷"
        case .add, .subtract, .power: return String(op.rawValue)
        default: return nil
        }
    }

    /// Rebuilds a token stream into equivalent calculator input for evaluating its complete prefix.
    private static func tokenQuery(_ tokens: [CalcToken]) -> String {
        tokens.map { token in
            switch token {
            case .number(let value), .compactNumber(let value):
                if let integer = Int64(exactly: value) { return String(integer) }
                return String(value)
            case .intLiteral(let value, let base):
                // Keep the radix prefix so `0xff -` still reports a hex source, not a decimal one.
                return base.prefix + String(value, radix: base.rawValue)
            case .ident(let name):
                return name
            case .op(let op):
                return op.text
            case .arrow:
                return "->"
            case .comma:
                return ","
            }
        }.joined(separator: " ")
    }

    private static func replacingExpression(_ result: CalcResult, with expression: String) -> CalcResult {
        CalcResult(
            expression: expression,
            sourceBadge: result.sourceBadge,
            targetBadge: result.targetBadge,
            payload: result.payload)
    }

    // MARK: - Number bases

    /// `255 to hex`, `2*128 to hex`: an expression on the left, like `CalcUnits.parseConversion`.
    private static func baseConversion(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard tokens.count >= 3, CalcUnits.isConnector(tokens[tokens.count - 2]),
            case .ident(let name) = tokens[tokens.count - 1], let target = CalcNumberBase(name: name)
        else { return nil }

        let valueTokens = Array(tokens[0..<(tokens.count - 2)])
        let literalText = query.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? query
        let source: UInt64
        let sourceBadge: String
        let sourceText: String
        if valueTokens.count == 1, case .intLiteral(let value, let base) = valueTokens[0] {
            source = value
            sourceBadge = base.name
            sourceText = literalText
        } else if valueTokens.count == 1, let value = decimalLiteral(valueTokens[0]),
            value >= 0, value.rounded() == value, value <= 9_007_199_254_740_992
        {
            source = UInt64(value)
            sourceBadge = "Decimal"
            sourceText = literalText
        } else if let value = CalcExpressionParser.scalar(valueTokens),
            value >= 0, value.rounded() == value, value <= 9_007_199_254_740_992
        {
            source = UInt64(value)
            sourceBadge = "Decimal"
            sourceText = CalcFormatter.grouped(String(source))
        } else {
            return nil
        }

        let output = target == .decimal ? CalcFormatter.grouped(String(source))
            : target.prefix + String(source, radix: target.rawValue, uppercase: true)
        return CalcResult(
            expression: sourceText,
            sourceBadge: sourceBadge,
            targetBadge: target.name,
            payload: .value(
                display: output, copyText: output.replacingOccurrences(of: ",", with: "")))
    }

    // Both spellings of a plain decimal literal — "255" and the compact "10k" — echo verbatim.
    private static func decimalLiteral(_ token: CalcToken) -> Double? {
        switch token {
        case .number(let value), .compactNumber(let value): return value
        default: return nil
        }
    }

}
