import Foundation

/// Typed arithmetic for measurements and currencies.
enum CalcQuantity {
    static func evaluate(
        _ tokens: [CalcToken], query: String, rates: CurrencyRates?, region: String? = nil,
        preserveStandaloneUnit: Bool = false
    ) -> CalcResult? {
        if tokens.count == 1, case .intLiteral = tokens[0] { return nil }
        let split = splitConversion(tokens)
        if let target = split.targetName, target != "timespan", target != "duration",
            isSimpleConversionSource(split.expressionTokens),
            CalcUnits.byName[target] != nil || CalcCurrency.byName[target] != nil {
            return nil
        }

        var parser = CalcExpressionParser(tokens: split.expressionTokens, rates: rates)
        guard let value = parser.parse() else {
            guard let message = parser.issue else { return nil }
            return CalcResult(expression: query, payload: .error(message: message))
        }
        if parser.dimensionCount == 0, !value.isBoolean {
            guard split.targetName == nil,
                parser.operationCount > 0 || (!preserveStandaloneUnit && tokens.count > 1) else { return nil }
            return CalcResult(expression: CalcFormatter.expression(query), sourceBadge: "Expression",
                targetBadge: "Result", payload: .number(value.effective))
        }
        if value.isBoolean {
            guard split.targetName == nil else { return nil }
            let text = value.amount == 0 ? "false" : "true"
            return CalcResult(expression: expressionText(split.expressionTokens), sourceBadge: "Expression",
                targetBadge: "Boolean", payload: .value(display: text, copyText: text))
        }

        if parser.usedCurrency && !parser.usedCurrencyRate {
            guard let rates else {
                return CalcResult(
                    expression: query,
                    payload: .error(
                        message: "Exchange rates unavailable — check your connection."))
            }
            if let code = parser.currencyCodes.first(where: { rates.rate(for: $0) == nil }) {
                return CalcResult(
                    expression: query,
                    payload: .error(message: "No exchange rate for \(code)."))
            }
        }

        if let targetName = split.targetName {
            if targetName == "timespan" || targetName == "duration" {
                guard case .unit(let unit) = value.kind, unit.category == .time else { return nil }
                let seconds = value.amount * unit.factor
                guard seconds.isFinite else { return nil }
                let text = CalcFormatter.timespan(seconds)
                return CalcResult(
                    expression: expressionText(split.expressionTokens),
                    sourceBadge: parser.operationCount == 0 ? unit.name : "Expression",
                    targetBadge: "Timespan", payload: .value(display: text, copyText: text))
            }
            guard let output = parser.converted(value, to: targetName) else {
                guard let message = parser.issue else { return nil }
                return CalcResult(expression: query, payload: .error(message: message))
            }
            return convertedResult(output, expression: expressionText(split.expressionTokens))
        }

        switch value.kind {
        case .scalar:
            guard parser.operationCount > 0 else { return nil }
            return CalcResult(
                expression: expressionText(split.expressionTokens),
                sourceBadge: "Expression", targetBadge: "Result",
                payload: .number(value.effective))
        case .unit(let unit):
            // A bare `50cm` auto-converts below; with an operator the typed units are kept.
            if !preserveStandaloneUnit, parser.operationCount == 0, parser.dimensionCount == 1,
                case .ident(let finalName)? = split.expressionTokens.last,
                CalcUnits.byName[finalName] != nil
            {
                return nil
            }
            guard parser.operationCount > 0 || parser.dimensionCount > 1 || preserveStandaloneUnit else { return nil }
            return measurementResult(
                value.amount, unit: unit, expression: expressionText(split.expressionTokens))
        case .currency(let definition):
            guard parser.operationCount == 0 else {
                return currencyResult(
                    value.amount, definition: definition,
                    expression: expressionText(split.expressionTokens))
            }
            let expression = "\(CalcFormatter.display(value.amount)) \(definition.code)"
            // A bare amount names no target, so the Mac's own currency becomes one once it's typed.
            guard !preserveStandaloneUnit, let target = regionTarget(region, from: definition),
                let output = rates?.convert(value.amount, from: definition.code, to: target.code)
            else {
                return currencyResult(value.amount, definition: definition, expression: expression)
            }
            return currencyResult(
                output, definition: target, expression: expression, sourceBadge: definition.name)
        }
    }

    /// Converting is the only reason to type a lone amount, so it pairs with the region's own.
    private static func regionTarget(_ region: String?, from: CurrencyDef) -> CurrencyDef? {
        guard let regional = region.flatMap({ CalcCurrency.byName[$0.lowercased()] })
        else { return nil }
        guard regional.code == from.code else { return regional }
        return CalcCurrency.byName[from.code == "USD" ? "eur" : "usd"]
    }

    private static func convertedResult(
        _ value: CalcValue, expression: String
    ) -> CalcResult? {
        switch value.kind {
        case .scalar:
            return nil
        case .unit(let unit):
            return measurementResult(value.amount, unit: unit, expression: expression)
        case .currency(let definition):
            return currencyResult(value.amount, definition: definition, expression: expression)
        }
    }

    private static func measurementResult(
        _ amount: Double, unit: UnitDef, expression: String
    ) -> CalcResult {
        CalcResult(
            expression: expression,
            sourceBadge: "Expression", targetBadge: unit.name,
            payload: .number(amount, suffix: " \(unit.symbol)"))
    }

    private static func currencyResult(
        _ amount: Double, definition: CurrencyDef, expression: String,
        sourceBadge: String = "Expression"
    ) -> CalcResult {
        let formatted = CalcFormatter.currency(amount)
        return CalcResult(
            expression: expression,
            sourceBadge: sourceBadge, targetBadge: definition.name,
            payload: .value(
                display: "\(CalcFormatter.grouped(formatted)) \(definition.code)",
                copyText: "\(formatted) \(definition.code)"))
    }

    static func convertUnit(_ amount: Double, from: UnitDef, to: UnitDef) -> Double {
        (amount * from.factor + from.offset - to.offset) / to.factor
    }

    private static func splitConversion(
        _ tokens: [CalcToken]
    ) -> (expressionTokens: [CalcToken], targetName: String?) {
        guard let target = conversionTarget(tokens, from: 0, to: tokens.count) else { return (tokens, nil) }
        return (Array(tokens[..<target.start]), target.name)
    }

    static func conversionTarget(
        _ tokens: [CalcToken], from start: Int, to end: Int
    ) -> (start: Int, name: String)? {
        var depth = 0
        for index in start..<end {
            if tokens[index] == .op(.open) { depth += 1 }
            if tokens[index] == .op(.close) { depth -= 1 }
            guard depth == 0, index + 1 < end, CalcUnits.isConnector(tokens[index]) else { continue }
            if index + 2 == end, case .ident(let name) = tokens[index + 1] { return (index, name) }
            let target = Array(tokens[(index + 1)..<end])
            guard CalcUnitExpression.parse(target) != nil else { continue }
            return (index, target.map { token in
                switch token {
                case .ident(let name): return name
                case .op(let op): return String(op.rawValue)
                case .number(let value): return CalcFormatter.copyText(value)
                default: return ""
                }
            }.joined(separator: " "))
        }
        return nil
    }

    private static func isSimpleConversionSource(_ tokens: [CalcToken]) -> Bool {
        switch tokens.count {
        case 1:
            if case .ident = tokens[0] { return true }
        case 2:
            switch (tokens[0], tokens[1]) {
            case (.number, .ident), (.compactNumber, .ident),
                (.ident, .number), (.ident, .compactNumber):
                return true
            default:
                break
            }
        default:
            break
        }
        return false
    }

    /// Normalized echo for the card's left column: symbols, pretty glyphs, `amount code` money.
    private static func expressionText(_ tokens: [CalcToken]) -> String {
        var parts: [String] = []
        parts.reserveCapacity(tokens.count)
        var attachNext = true

        func add(_ piece: String, attached: Bool = false) {
            if attachNext || attached, !parts.isEmpty {
                parts[parts.count - 1] += piece
            } else {
                parts.append(piece)
            }
            attachNext = false
        }

        var index = 0
        while index < tokens.count {
            // Money is written sign-first (`$10`), so echo the amount ahead of its code.
            if case .ident(let name) = tokens[index], CalcUnits.byName[name] == nil,
                let definition = CalcCurrency.byName[name], index + 1 < tokens.count,
                let amount = numberValue(tokens[index + 1])
            {
                add(CalcFormatter.copyText(amount))
                add(definition.code)
                index += 2
                continue
            }

            switch tokens[index] {
            case .number(let value), .compactNumber(let value):
                add(CalcFormatter.copyText(value))
            case .intLiteral(let value, _):
                add(String(value))
            case .ident(let name):
                add(CalcUnits.byName[name]?.symbol ?? CalcCurrency.byName[name]?.code ?? name)
            case .op(.open):
                add("(")
                attachNext = true
            case .op(.close):
                add(")", attached: true)
            case .op(.percent):
                add("%", attached: true)
            case .op(.factorial):
                add("!", attached: true)
            case .op(.multiply):
                add("×")
            case .op(.divide):
                add("÷")
            case .op(let op):
                add(op.text)
                if op == .subtract || op == .add { attachNext = isSign(at: index, tokens) }
            case .arrow:
                add("→")
            case .comma:
                add(",", attached: true)
            }
            index += 1
        }
        return parts.joined(separator: " ")
    }

    /// True when `+`/`-` negates the operand that follows rather than joining two of them.
    private static func isSign(at index: Int, _ tokens: [CalcToken]) -> Bool {
        guard index > 0 else { return true }
        if case .op(let previous) = tokens[index - 1] {
            return previous != .close && previous != .percent && previous != .factorial
        }
        return false
    }

    static func numberValue(_ token: CalcToken) -> Double? {
        switch token {
        case .number(let value), .compactNumber(let value):
            return value
        default:
            return nil
        }
    }
}
