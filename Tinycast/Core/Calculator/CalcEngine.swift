import Foundation

/// A single evaluated calculator answer for the launcher's inline card.
struct CalcResult: Equatable, Sendable {
    enum Payload: Equatable, Sendable {
        /// `display` is grouped and human-facing ("1,234,567"); `copyText` is the same answer without grouping, for pasting onwards.
        case value(display: String, copyText: String)
        /// A friendly error ("Cannot convert Weight to Time.") — only for a clear conversion attempt, never a half-typed expression.
        case error(message: String)
    }

    /// Normalized echo of what was evaluated, shown on the card's left side ("3×3", "10 km").
    let expression: String
    /// Optional word-name pills beneath each side of the card ("Meters"→"Feet", "12:18 AM"→"9:00 AM"); nil for plain arithmetic.
    let sourceBadge: String?
    let targetBadge: String?
    let payload: Payload

    init(expression: String, sourceBadge: String? = nil, targetBadge: String? = nil, payload: Payload) {
        self.expression = expression
        self.sourceBadge = sourceBadge
        self.targetBadge = targetBadge
        self.payload = payload
    }

    /// True only for a copyable value — error cards are informational and have no primary action or actions menu.
    var isActionable: Bool {
        if case .value = payload { return true }
        return false
    }
}

/// Entry point turning a raw query into a calculator answer (or nil when it isn't calculator input), via a pure pre-filter → base → unit → quantity → arithmetic pipeline; kept Foundation-only so `Tools/calc-test.swift` compiles it standalone.
enum CalcEngine {
    /// Public entry: evaluates against the live clock. `currency` defaults to `.off` so any caller that
    /// hasn't been handed a consented source gets the feature disabled rather than silently enabled.
    static func evaluate(_ raw: String, currency: CurrencySource = .off) -> CalcResult? {
        evaluate(raw, now: Date(), calendar: .current, currency: currency)
    }

    /// `now`/`calendar` are injected so the date/time paths are deterministic under `Tools/calc-test.swift`.
    static func evaluate(
        _ raw: String, now: Date, calendar: Calendar, currency: CurrencySource = .off
    ) -> CalcResult? {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 256 else { return nil }

        // Date/time first: `hrs till july` carries no digit, so it must run before the numeric reject below.
        if let dateTime = CalcDateTime.evaluate(query, now: now, calendar: calendar) { return dateTime }

        guard let tokens = CalcTokenizer.tokenize(query), !tokens.isEmpty else { return nil }

        if let partial = partialResult(
            tokens, query: query, now: now, calendar: calendar, currency: currency)
        {
            return partial
        }

        // A lone literal or constant is more likely an app search than a calculation, so no card — except a radix literal ("0xff"), where echoing the decimal is useful.
        if tokens.count == 1 {
            if case .intLiteral(let value, let radix) = tokens[0], radix != 10 {
                let display = CalcFormatter.grouped(String(value))
                return CalcResult(
                    expression: query,
                    sourceBadge: "Hexadecimal", targetBadge: "Decimal",
                    payload: .value(display: display, copyText: String(value)))
            }
            if case .compactNumber(let value) = tokens[0] {
                return CalcResult(
                    expression: query,
                    sourceBadge: "Expression", targetBadge: "Result",
                    payload: .value(
                        display: CalcFormatter.display(value),
                        copyText: CalcFormatter.copyText(value)))
            }
            return nil
        }

        if let base = baseConversion(tokens, query: query) { return base }

        // Conversions run before the numeric reject below: `m to ft`, `day s` carry no digit.
        if let conversion = CalcUnits.parseConversion(tokens) ?? CalcUnits.parseUnitPairConversion(tokens) {
            switch conversion {
            case .value(let input, let from, let to, let output):
                return CalcResult(
                    expression: "\(CalcFormatter.display(input)) \(from.symbol)",
                    sourceBadge: from.name,
                    targetBadge: to.name,
                    payload: .value(
                        display: "\(CalcFormatter.display(output)) \(to.symbol)",
                        copyText: "\(CalcFormatter.copyText(output)) \(to.symbol)"))
            case .mismatch(let from, let to):
                return CalcResult(
                    expression: query,
                    payload: .error(
                        message:
                            "Cannot convert \(from.category.displayName) to \(to.category.displayName)."
                    ))
            }
        }

        // Run typed arithmetic before currency conversion so unit aliases such as `pounds` keep winning in multi-term expressions.
        if let quantity = CalcQuantity.evaluate(tokens, query: query, currency: currency) {
            return quantity
        }

        // Currency runs after units so an all-unit query keeps winning: `10 pounds to kg` is weight,
        // `10 pounds to euros` is money. Returns nil outright when the user hasn't consented.
        if let conversion = CalcCurrency.parseConversion(tokens, source: currency) {
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
            let display =
                bare.compound
                ? CalcFormatter.compoundFeetInches(bare.output)
                : "\(CalcFormatter.display(bare.output)) \(bare.to.symbol)"
            let copyText =
                bare.compound
                ? display : "\(CalcFormatter.copyText(bare.output)) \(bare.to.symbol)"
            return CalcResult(
                expression: "\(CalcFormatter.display(bare.input)) \(bare.from.symbol)",
                sourceBadge: bare.from.name,
                targetBadge: bare.to.name,
                payload: .value(display: display, copyText: copyText))
        }

        // Natural-language percent: `20% off 500`, `50 as % of 200`.
        if let percent = CalcPercent.evaluate(tokens, query: query) { return percent }

        // Cheap reject for the arithmetic fallback: plain math always carries a digit or a constant, keeping the common app-search case a no-card.
        guard
            query.contains(where: { $0.isASCII && $0.isNumber })
                || query.lowercased().contains("e") || query.contains("π")
        else { return nil }

        guard let value = CalcParser.evaluate(tokens) else { return nil }
        return CalcResult(
            expression: prettyExpression(query),
            sourceBadge: "Expression",
            targetBadge: "Result",
            payload: .value(
                display: CalcFormatter.display(value),
                copyText: CalcFormatter.copyText(value)))
    }

    // MARK: - Partial expressions

    /// A trailing binary operator keeps the last complete prefix visible and copyable while the user types the right operand.
    private static func partialResult(
        _ tokens: [CalcToken], query: String, now: Date, calendar: Calendar,
        currency: CurrencySource
    ) -> CalcResult? {
        guard let trailing = tokens.last, let operatorText = partialOperatorText(trailing) else {
            return nil
        }
        let prefixTokens = Array(tokens.dropLast())
        guard !prefixTokens.isEmpty else { return nil }

        if let quantity = CalcQuantity.evaluate(
            prefixTokens, query: tokenQuery(prefixTokens), currency: currency,
            preserveStandaloneUnit: true)
        {
            return replacingExpression(
                quantity, with: "\(quantity.expression) \(operatorText)")
        }

        // A conversion's own echo drops its target ("10 km" for `10km to mi`), so echo the typed text instead — the badges still name both units.
        if let complete = evaluate(
            tokenQuery(prefixTokens), now: now, calendar: calendar, currency: currency)
        {
            return replacingExpression(complete, with: prettyExpression(query))
        }

        guard let value = CalcParser.evaluate(prefixTokens) else { return nil }
        return CalcResult(
            expression: prettyExpression(query),
            sourceBadge: "Expression", targetBadge: "Result",
            payload: .value(
                display: CalcFormatter.display(value),
                copyText: CalcFormatter.copyText(value)))
    }

    private static func partialOperatorText(_ token: CalcToken) -> String? {
        guard case .op(let op) = token else { return nil }
        switch op {
        case "*": return "×"
        case "/": return "÷"
        case "+", "-", "^": return String(op)
        default: return nil
        }
    }

    /// Rebuilds a token stream into equivalent calculator input for evaluating its complete prefix.
    private static func tokenQuery(_ tokens: [CalcToken]) -> String {
        tokens.map { token in
            switch token {
            case .number(let value), .compactNumber(let value):
                return CalcFormatter.copyText(value)
            case .intLiteral(let value, let radix):
                // Keep the radix prefix so `0xff -` still reports a hex source, not a decimal one.
                let prefix = [16: "0x", 2: "0b", 8: "0o"][radix] ?? ""
                return prefix + String(value, radix: radix)
            case .ident(let name):
                return name
            case .op(let op):
                return String(op)
            case .arrow:
                return "->"
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

    /// `255 to hex`, `0xff to decimal`, `0b1010 to binary`, `2*128 to hex` — value expression,
    /// connector, target; mirrors how `CalcUnits.parseConversion` allows an expression on the left
    /// (`2*5 km to mi`) rather than only a bare literal.
    private static func baseConversion(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard tokens.count >= 3, CalcUnits.isConnector(tokens[tokens.count - 2]),
            case .ident(let target) = tokens[tokens.count - 1]
        else { return nil }

        let valueTokens = Array(tokens[0..<(tokens.count - 2)])
        let literalText = query.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? query
        let source: UInt64
        let sourceBadge: String
        let sourceText: String
        if valueTokens.count == 1, case .intLiteral(let value, let radix) = valueTokens[0] {
            source = value
            sourceBadge = baseName(forRadix: radix)
            sourceText = literalText
        } else if valueTokens.count == 1, let value = decimalLiteral(valueTokens[0]),
            value >= 0, value.rounded() == value, value <= 9_007_199_254_740_992
        {
            source = UInt64(value)
            sourceBadge = "Decimal"
            sourceText = literalText
        } else if let value = CalcParser.evaluate(valueTokens),
            value >= 0, value.rounded() == value, value <= 9_007_199_254_740_992
        {
            source = UInt64(value)
            sourceBadge = "Decimal"
            sourceText = CalcFormatter.grouped(String(source))
        } else {
            return nil
        }

        let output: String
        let targetBadge: String
        switch target {
        case "hex", "hexadecimal":
            output = "0x" + String(source, radix: 16, uppercase: true)
            targetBadge = "Hexadecimal"
        case "binary", "bin":
            output = "0b" + String(source, radix: 2)
            targetBadge = "Binary"
        case "octal", "oct":
            output = "0o" + String(source, radix: 8)
            targetBadge = "Octal"
        case "decimal", "dec":
            output = CalcFormatter.grouped(String(source))
            targetBadge = "Decimal"
        default:
            return nil
        }
        return CalcResult(
            expression: sourceText,
            sourceBadge: sourceBadge,
            targetBadge: targetBadge,
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

    private static func baseName(forRadix radix: Int) -> String {
        switch radix {
        case 16: return "Hexadecimal"
        case 2: return "Binary"
        case 8: return "Octal"
        default: return "Decimal"
        }
    }

    /// Light cleanup of the typed expression for the card: collapse whitespace and use pretty operator glyphs, otherwise keep what the user wrote.
    private static func prettyExpression(_ query: String) -> String {
        query.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .replacingOccurrences(of: "*", with: "×")
            .replacingOccurrences(of: "/", with: "÷")
    }
}
