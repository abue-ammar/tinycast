import Foundation

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

        /// CSS lengths copy unspaced ("24px") so the answer pastes straight into a stylesheet.
        static func measurement(_ value: Double, unit: UnitDef) -> Self {
            let text = CalcFormatter.copyText(value)
            let copySeparator = unit.category == .pixels ? "" : " "
            return .value(
                display: "\(CalcFormatter.grouped(text)) \(unit.symbol)",
                copyText: text + copySeparator + unit.symbol)
        }

        static func money(_ amount: Double, code: String) -> Self {
            let text = CalcFormatter.currency(amount)
            return .value(display: "\(CalcFormatter.grouped(text)) \(code)", copyText: "\(text) \(code)")
        }

        static func quantity(_ value: CalcValue) -> Self {
            switch value.kind {
            case .scalar: .number(value.effective)
            case .unit(let unit): .measurement(value.amount, unit: unit)
            case .currency(let currency): .money(value.amount, code: currency.code)
            }
        }
    }

    /// Normalized echo of what was evaluated, shown on the card's left side ("3×3", "10 km").
    let expression: String
    /// Optional word-name pills beneath each side; nil for plain arithmetic.
    let sourceBadge: String?
    let targetBadge: String?
    let payload: Payload
    /// False when the copy text, typed back as a query, is not this answer: dates, times, booleans.
    let canChain: Bool
    let isCurrency: Bool

    init(
        expression: String, sourceBadge: String? = nil, targetBadge: String? = nil, payload: Payload,
        canChain: Bool = true, isCurrency: Bool = false
    ) {
        self.expression = expression
        self.sourceBadge = sourceBadge
        self.targetBadge = targetBadge
        self.payload = payload
        self.canChain = canChain
        self.isCurrency = isCurrency
    }

    /// A phrase's card: the query echoed with its spacing collapsed, badged by what it answers.
    static func phrase(
        _ query: String, _ payload: Payload, target: String, canChain: Bool = true, isCurrency: Bool = false
    ) -> CalcResult {
        CalcResult(
            expression: query.split(whereSeparator: \.isWhitespace).joined(separator: " "),
            sourceBadge: String(localized: "Expression"), targetBadge: target, payload: payload,
            canChain: canChain, isCurrency: isCurrency)
    }

    /// True only for a copyable value; an error card has no primary action and no actions menu.
    var isActionable: Bool {
        if case .value = payload { return true }
        return false
    }
}

enum CalcEngine {
    /// Every environment fact is injected; the answer is canonical, for `format` to localize.
    static func evaluate(
        _ raw: String, now: Date, calendar: Calendar, rates: CurrencyRates? = nil,
        region: String? = nil, format: CalcNumberFormat = .english
    ) -> CalcResult? {
        let trimmed = withoutQuestionMark(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !trimmed.isEmpty, trimmed.count <= 256, let query = format.canonical(trimmed) else {
            return nil
        }
        if query.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) }) {
            return CalcDateTime.namedMoment(query, now: now, calendar: calendar).map(unchained)
        }
        // The remainder is already canonical, so it must not be re-read in the localized format.
        if let asked = CalcQuestion.asked(query),
            let answer = evaluate(asked, now: now, calendar: calendar, rates: rates, region: region)
        {
            return answer
        }

        if let fact = CalcDateFacts.evaluate(query, now: now, calendar: calendar) {
            return unchained(sightingNoted(fact, query: query))
        }

        if let dateTime = CalcDateTime.evaluate(query, now: now, calendar: calendar) {
            return unchained(sightingNoted(dateTime, query: query))
        }

        // Before tokenizing: `5pm ldn in sf` is words, which the tokenizer would reject.
        if let zone = CalcTimeZone.evaluate(query, now: now, calendar: calendar) {
            return unchained(zone)
        }

        guard let typed = CalcTokenizer.tokenize(query), !typed.isEmpty else { return nil }
        let tokens = CalcQuestion.conversion(typed) ?? typed

        if CalcSplit.mentions(tokens), let share = CalcSplit.evaluate(query, rates: rates, region: region) {
            return share
        }

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
                    sourceBadge: base.name, targetBadge: String(localized: "Decimal"),
                    payload: .value(display: display, copyText: String(value)))
            }
            if case .compactNumber(let value) = tokens[0] {
                return CalcResult(
                    expression: query,
                    sourceBadge: String(localized: "Expression"), targetBadge: String(localized: "Result"),
                    payload: .number(value))
            }
            return nil
        }

        if let base = baseConversion(tokens, query: query) { return base }
        if let form = CalcNumberForm.evaluate(tokens, query: query) { return form }

        // Typed arithmetic first, so aliases such as `pounds` keep winning in multi-term exprs.
        if let quantity = CalcQuantity.evaluate(tokens, query: query, rates: rates, region: region),
            quantity.isActionable || !CalcCurrency.isPair(tokens)
        {
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
                    payload: .measurement(output, unit: to))
            case .mismatch(let from, let to):
                return CalcResult(
                    expression: query,
                    payload: .error(
                        message: String(
                            localized:
                                "Cannot convert \(from.category.displayName) to \(to.category.displayName)."
                        )))
            }
        }

        // After units, so `10 pounds to kg` stays weight.
        if let conversion = CalcCurrency.parseConversion(tokens, rates: rates) {
            switch conversion {
            case .value(let input, let from, let to, let output):
                return CalcResult(
                    expression: "\(CalcFormatter.display(input)) \(from.code)",
                    sourceBadge: from.name,
                    targetBadge: to.name,
                    payload: .money(output, code: to.code),
                    isCurrency: true)
            case .mismatch(let from, let to):
                return CalcResult(
                    expression: query,
                    payload: .error(message: String(localized: "Cannot convert \(from) to \(to).")))
            case .noRate(let code):
                return CalcResult(
                    expression: query,
                    payload: .error(message: String(localized: "No exchange rate for \(code).")))
            case .unavailable:
                return CalcResult(
                    expression: query,
                    payload: .error(
                        message: String(localized: "Exchange rates unavailable — check your connection.")))
            }
        }

        if let bare = CalcUnits.parseBareConversion(tokens) {
            let payload: CalcResult.Payload
            if bare.compound {
                let text = CalcFormatter.compoundFeetInches(bare.output)
                payload = .value(display: text, copyText: text)
            } else {
                payload = .measurement(bare.output, unit: bare.to)
            }
            return CalcResult(
                expression: "\(CalcFormatter.display(bare.input)) \(bare.from.symbol)",
                sourceBadge: bare.from.name,
                targetBadge: bare.to.name,
                payload: payload)
        }

        return CalcPercent.evaluate(tokens, query: query) ?? CalcRounding.evaluate(tokens, query: query)
            ?? CalcFinance.evaluate(tokens, query: query) ?? CalcGrowth.evaluate(tokens, query: query)
            ?? CalcSpokenMath.evaluate(tokens, query: query)
            ?? CalcStatistics.evaluate(tokens, query: query) ?? CalcRatePhrases.evaluate(tokens, query: query)
            ?? CalcSubstance.evaluate(tokens, query: query) ?? CalcPixelDensity.evaluate(tokens, query: query)
            ?? CalcPitch.evaluate(tokens, query: query)
    }

    private static func withoutQuestionMark(_ text: String) -> String {
        guard text.hasSuffix("?") else { return text }
        return String(text.dropLast()).trimmingCharacters(in: .whitespaces)
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
            return CalcResult(
                expression: CalcFormatter.expression(query),
                sourceBadge: String(localized: "Expression"), targetBadge: String(localized: "Result"),
                payload: .number(value))
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
            sourceBadge: String(localized: "Expression"), targetBadge: String(localized: "Result"),
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
            payload: result.payload,
            canChain: result.canChain,
            isCurrency: result.isCurrency)
    }

    /// A day set by moon sighting can move by one, so the card says so; the copy stays exact.
    private static func sightingNoted(_ result: CalcResult, query: String) -> CalcResult {
        guard CalcHolidays.mentionsSightedDay(query), case .value(let display, let copyText) = result.payload
        else { return result }
        return CalcResult(
            expression: result.expression,
            sourceBadge: result.sourceBadge,
            targetBadge: result.targetBadge,
            payload: .value(display: display + " " + String(localized: "(±1 day)"), copyText: copyText),
            canChain: result.canChain,
            isCurrency: result.isCurrency)
    }

    private static func unchained(_ result: CalcResult) -> CalcResult {
        CalcResult(
            expression: result.expression,
            sourceBadge: result.sourceBadge,
            targetBadge: result.targetBadge,
            payload: result.payload,
            canChain: false)
    }

    // MARK: - Number bases

    /// `255 to hex`, `2*128 to hex`: an expression on the left, like `CalcUnits.parseConversion`.
    private static func baseConversion(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard let target = radixTarget(tokens) else { return nil }

        let valueTokens = Array(tokens[..<target.start])
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
            sourceBadge = String(localized: "Decimal")
            sourceText = literalText
        } else if let value = CalcExpressionParser.scalar(valueTokens),
            value >= 0, value.rounded() == value, value <= 9_007_199_254_740_992
        {
            source = UInt64(value)
            sourceBadge = String(localized: "Decimal")
            sourceText = CalcFormatter.grouped(String(source))
        } else {
            return nil
        }

        let output =
            target.radix == 10
            ? CalcFormatter.grouped(String(source))
            : target.prefix + String(source, radix: target.radix, uppercase: true)
        return CalcResult(
            expression: sourceText,
            sourceBadge: sourceBadge,
            targetBadge: target.name,
            payload: .value(
                display: output, copyText: output.replacingOccurrences(of: ",", with: "")))
    }

    private static func radixTarget(
        _ tokens: [CalcToken]
    ) -> (start: Int, radix: Int, prefix: String, name: String)? {
        let count = tokens.count
        if count >= 3, CalcUnits.isConnector(tokens[count - 2]), case .ident(let name) = tokens[count - 1],
            let base = CalcNumberBase(name: name)
        {
            return (count - 2, base.rawValue, base.prefix, base.name)
        }
        guard count >= 4, CalcUnits.isConnector(tokens[count - 3]), tokens[count - 2] == .ident("base"),
            let radix = decimalLiteral(tokens[count - 1]).flatMap({ Int(exactly: $0) }),
            (2...36).contains(radix)
        else { return nil }
        if let base = CalcNumberBase(rawValue: radix) { return (count - 3, radix, base.prefix, base.name) }
        return (count - 3, radix, "", String(localized: "Base \(radix)"))
    }

    // Both spellings of a plain decimal literal — "255" and the compact "10k" — echo verbatim.
    private static func decimalLiteral(_ token: CalcToken) -> Double? {
        switch token {
        case .number(let value), .compactNumber(let value): return value
        default: return nil
        }
    }

}
