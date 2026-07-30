import Foundation

/// Typed arithmetic for measurements and consent-gated currencies.
enum CalcQuantity {
    static func evaluate(
        _ tokens: [CalcToken], query: String, currency: CurrencySource,
        preserveStandaloneUnit: Bool = false
    ) -> CalcResult? {
        let split = splitConversion(tokens)
        if split.targetName != nil, isSimpleConversionSource(split.expressionTokens) {
            return nil
        }

        var parser = QuantityParser(tokens: split.expressionTokens, currency: currency)
        guard let value = parser.parse() else {
            guard let message = parser.issue else { return nil }
            return CalcResult(expression: query, payload: .error(message: message))
        }
        guard parser.dimensionCount > 0 else { return nil }

        if parser.usedCurrency {
            switch currency {
            case .off:
                return nil
            case .on(nil):
                return CalcResult(
                    expression: query,
                    payload: .error(
                        message: "Exchange rates unavailable — check your connection."))
            case .on(let rates?):
                if let code = parser.currencyCodes.first(where: { rates.rate(for: $0) == nil }) {
                    return CalcResult(
                        expression: query,
                        payload: .error(message: "No exchange rate for \(code)."))
                }
            }
        }

        if let targetName = split.targetName {
            return convertedResult(
                value, targetName: targetName, expressionTokens: split.expressionTokens,
                query: query, currency: currency)
        }

        switch value.kind {
        case .scalar:
            guard parser.operationCount > 0 else { return nil }
            return CalcResult(
                expression: expressionText(split.expressionTokens),
                sourceBadge: "Expression", targetBadge: "Result",
                payload: .value(
                    display: CalcFormatter.display(value.effective),
                    copyText: CalcFormatter.copyText(value.effective)))
        case .unit(let unit):
            // A bare `50cm` belongs to the auto-conversion path below; once an operator is involved the
            // answer stays in the units the user wrote, so `2 * 5kg` is `10 kg`, not `22.05 lb`.
            if !preserveStandaloneUnit, parser.operationCount == 0, parser.dimensionCount == 1,
                case .ident(let finalName)? = split.expressionTokens.last,
                CalcUnits.byName[finalName] != nil
            {
                return nil
            }
            guard parser.operationCount > 0 || preserveStandaloneUnit else { return nil }
            return measurementResult(
                value.amount, unit: unit, expression: expressionText(split.expressionTokens))
        case .currency(let definition):
            return currencyResult(
                value.amount, definition: definition,
                expression:
                    parser.operationCount == 0
                    ? "\(CalcFormatter.display(value.amount)) \(definition.code)"
                    : expressionText(split.expressionTokens))
        }
    }

    private static func convertedResult(
        _ value: QuantityValue, targetName: String, expressionTokens: [CalcToken],
        query: String, currency: CurrencySource
    ) -> CalcResult? {
        let expression = expressionText(expressionTokens)
        switch value.kind {
        case .scalar:
            return nil
        case .unit(let from):
            if let to = CalcUnits.byName[targetName] {
                guard from.category == to.category else {
                    return conversionError(
                        query, from: from.category.displayName, to: to.category.displayName)
                }
                let output = convertUnit(value.amount, from: from, to: to)
                guard output.isFinite else { return nil }
                return measurementResult(output, unit: to, expression: expression)
            }
            if case .on = currency, CalcCurrency.byName[targetName] != nil {
                return conversionError(
                    query, from: from.category.displayName, to: CalcCurrency.categoryName)
            }
            return nil
        case .currency(let from):
            if case .on(let rates) = currency, let to = CalcCurrency.byName[targetName] {
                guard let rates else {
                    return CalcResult(
                        expression: query,
                        payload: .error(
                            message: "Exchange rates unavailable — check your connection."))
                }
                guard rates.rate(for: from.code) != nil else {
                    return CalcResult(
                        expression: query,
                        payload: .error(message: "No exchange rate for \(from.code)."))
                }
                guard rates.rate(for: to.code) != nil else {
                    return CalcResult(
                        expression: query,
                        payload: .error(message: "No exchange rate for \(to.code)."))
                }
                guard let output = rates.convert(value.amount, from: from.code, to: to.code)
                else { return nil }
                return currencyResult(output, definition: to, expression: expression)
            }
            if let to = CalcUnits.byName[targetName] {
                return conversionError(
                    query, from: CalcCurrency.categoryName, to: to.category.displayName)
            }
            return nil
        }
    }

    private static func measurementResult(
        _ amount: Double, unit: UnitDef, expression: String
    ) -> CalcResult {
        CalcResult(
            expression: expression,
            sourceBadge: "Expression", targetBadge: unit.name,
            payload: .value(
                display: "\(CalcFormatter.display(amount)) \(unit.symbol)",
                copyText: "\(CalcFormatter.copyText(amount)) \(unit.symbol)"))
    }

    private static func currencyResult(
        _ amount: Double, definition: CurrencyDef, expression: String
    ) -> CalcResult {
        let formatted = CalcFormatter.currency(amount)
        return CalcResult(
            expression: expression,
            sourceBadge: "Expression", targetBadge: definition.name,
            payload: .value(
                display: "\(CalcFormatter.grouped(formatted)) \(definition.code)",
                copyText: "\(formatted) \(definition.code)"))
    }

    private static func conversionError(_ query: String, from: String, to: String) -> CalcResult {
        CalcResult(
            expression: query,
            payload: .error(message: "Cannot convert \(from) to \(to)."))
    }

    fileprivate static func convertUnit(_ amount: Double, from: UnitDef, to: UnitDef) -> Double {
        (amount * from.factor + from.offset - to.offset) / to.factor
    }

    private static func splitConversion(
        _ tokens: [CalcToken]
    ) -> (expressionTokens: [CalcToken], targetName: String?) {
        guard tokens.count >= 3, CalcUnits.isConnector(tokens[tokens.count - 2]),
            case .ident(let targetName) = tokens[tokens.count - 1]
        else { return (tokens, nil) }

        var depth = 0
        for token in tokens.dropLast(2) {
            if case .op("(") = token { depth += 1 }
            if case .op(")") = token { depth -= 1 }
        }
        guard depth == 0 else { return (tokens, nil) }
        return (Array(tokens.dropLast(2)), targetName)
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

    /// Normalized echo for the card's left column: unit symbols, pretty operator glyphs, money in `amount code` order, and signs / parentheses / postfix `%` `!` hugging their operand instead of standing alone as words.
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
            // Money is written sign-first (`$10`), so echo the amount ahead of its code like every other quantity.
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
            case .op("("):
                add("(")
                attachNext = true
            case .op(")"):
                add(")", attached: true)
            case .op("%"):
                add("%", attached: true)
            case .op("!"):
                add("!", attached: true)
            case .op("*"):
                add("×")
            case .op("/"):
                add("÷")
            case .op(let op):
                add(String(op))
                if op == "-" || op == "+" { attachNext = isSign(at: index, tokens) }
            case .arrow:
                add("→")
            }
            index += 1
        }
        return parts.joined(separator: " ")
    }

    /// True when `+`/`-` negates the operand that follows rather than joining two of them.
    private static func isSign(at index: Int, _ tokens: [CalcToken]) -> Bool {
        guard index > 0 else { return true }
        if case .op(let previous) = tokens[index - 1] {
            return previous != ")" && previous != "%" && previous != "!"
        }
        return false
    }

    fileprivate static func numberValue(_ token: CalcToken) -> Double? {
        switch token {
        case .number(let value), .compactNumber(let value):
            return value
        default:
            return nil
        }
    }
}

private struct QuantityValue {
    enum Kind {
        case scalar
        case unit(UnitDef)
        case currency(CurrencyDef)
    }

    var amount: Double
    var kind: Kind
    var isPercent = false

    var effective: Double {
        isPercent ? amount / 100 : amount
    }
}

private struct QuantityParser {
    let tokens: [CalcToken]
    let currency: CurrencySource
    var position = 0
    var operationCount = 0
    var dimensionCount = 0
    var usedCurrency = false
    var currencyCodes: [String] = []
    var issue: String?

    private static let unaryBindingPower = 25

    private var current: CalcToken? {
        position < tokens.count ? tokens[position] : nil
    }

    private var currencyEnabled: Bool {
        if case .on = currency { return true }
        return false
    }

    mutating func parse() -> QuantityValue? {
        guard let value = parseExpression(minBindingPower: 0), position == tokens.count,
            value.effective.isFinite
        else { return nil }
        return value
    }

    private mutating func parseExpression(minBindingPower: Int) -> QuantityValue? {
        guard var left = parseOperand() else { return nil }
        while let binary = peekBinary(left: left), binary.bindingPower >= minBindingPower {
            if binary.consumesToken { position += 1 }
            operationCount += 1
            guard
                let right = parseExpression(minBindingPower: binary.rightBindingPower),
                let combined = apply(
                    binary.op, left, right, implicit: !binary.consumesToken)
            else { return nil }
            left = combined
        }
        return left
    }

    private func peekBinary(
        left: QuantityValue
    ) -> (op: Character, bindingPower: Int, rightBindingPower: Int, consumesToken: Bool)? {
        switch current {
        case .op(let op) where op == "+" || op == "-":
            return (op, 10, 11, true)
        case .op(let op) where op == "*" || op == "/":
            return (op, 20, 21, true)
        case .ident("of"):
            return ("*", 20, 21, true)
        case .op("^"):
            return ("^", 30, 30, true)
        default:
            // Juxtaposition against a bracket multiplies (`$5(2)`, `5(2)$`), matching the scalar parser.
            if case .op("(") = current { return ("*", 20, 21, false) }
            if !isScalar(left.kind), startsQuantity(current) {
                return ("+", 10, 11, false)
            }
            return nil
        }
    }

    private mutating func apply(
        _ op: Character, _ left: QuantityValue, _ right: QuantityValue, implicit: Bool
    ) -> QuantityValue? {
        switch op {
        case "+", "-":
            return addOrSubtract(op, left, right, implicit: implicit)
        case "*":
            return multiply(left, right)
        case "/":
            return divide(left, right)
        case "^":
            guard isScalar(left.kind), isScalar(right.kind) else { return nil }
            let output = pow(left.effective, right.effective)
            return output.isFinite ? QuantityValue(amount: output, kind: .scalar) : nil
        default:
            return nil
        }
    }

    private mutating func addOrSubtract(
        _ op: Character, _ left: QuantityValue, _ right: QuantityValue, implicit: Bool
    ) -> QuantityValue? {
        let direction = op == "+" ? 1.0 : -1.0
        if right.isPercent {
            let output = left.effective * (1 + direction * right.amount / 100)
            return QuantityValue(amount: output, kind: left.kind)
        }

        switch (left.kind, right.kind) {
        case (.scalar, .scalar):
            return QuantityValue(
                amount: left.effective + direction * right.effective, kind: .scalar)
        case (.unit(let lhs), .unit(let rhs)):
            guard lhs.category == rhs.category else {
                return fail(
                    "Cannot \(op == "+" ? "add" : "subtract") \(lhs.category.displayName) and \(rhs.category.displayName)."
                )
            }
            if lhs.category == .temperature, lhs.symbol != rhs.symbol {
                return fail("Cannot combine temperatures with different units.")
            }
            // Composite notation ("5 feet 3 inches") reads as one quantity in its leading unit; an explicit `+`/`-` answers in the last unit typed.
            if implicit {
                let converted = CalcQuantity.convertUnit(right.amount, from: rhs, to: lhs)
                return QuantityValue(
                    amount: left.amount + direction * converted, kind: .unit(lhs))
            }
            let converted = CalcQuantity.convertUnit(left.amount, from: lhs, to: rhs)
            return QuantityValue(
                amount: converted + direction * right.amount, kind: .unit(rhs))
        case (.currency(let lhs), .currency(let rhs)):
            if implicit {
                guard let converted = convertedCurrency(right.amount, from: rhs, to: lhs)
                else { return nil }
                return QuantityValue(
                    amount: left.amount + direction * converted, kind: .currency(lhs))
            }
            guard let converted = convertedCurrency(left.amount, from: lhs, to: rhs)
            else { return nil }
            return QuantityValue(
                amount: converted + direction * right.amount, kind: .currency(rhs))
        case (.unit(let lhs), .currency):
            return fail(
                "Cannot \(op == "+" ? "add" : "subtract") \(lhs.category.displayName) and Currency."
            )
        case (.currency, .unit(let rhs)):
            return fail(
                "Cannot \(op == "+" ? "add" : "subtract") Currency and \(rhs.category.displayName)."
            )
        // A bare number takes the unit it is written against ("10kg + 5" is 15 kg). Adjacency stays
        // silent instead, because there the bare number is a half-typed unit ("1hr 30" → "1hr 30min").
        case (.unit, .scalar), (.currency, .scalar):
            guard !implicit else { return nil }
            return QuantityValue(
                amount: left.amount + direction * right.effective, kind: left.kind)
        case (.scalar, .unit), (.scalar, .currency):
            guard !implicit else { return nil }
            return QuantityValue(
                amount: left.effective + direction * right.amount, kind: right.kind)
        }
    }

    private mutating func multiply(
        _ left: QuantityValue, _ right: QuantityValue
    ) -> QuantityValue? {
        switch (left.kind, right.kind) {
        case (.scalar, .scalar):
            return QuantityValue(amount: left.effective * right.effective, kind: .scalar)
        case (.scalar, _):
            return QuantityValue(
                amount: left.effective * right.effective, kind: right.kind)
        case (_, .scalar):
            return QuantityValue(
                amount: left.effective * right.effective, kind: left.kind)
        default:
            return fail("Multiplication of two unit values is not supported.")
        }
    }

    private mutating func divide(
        _ left: QuantityValue, _ right: QuantityValue
    ) -> QuantityValue? {
        switch (left.kind, right.kind) {
        case (.scalar, .scalar):
            return finiteDivision(left.effective, right.effective, kind: .scalar)
        case (.unit, .scalar), (.currency, .scalar):
            return finiteDivision(left.effective, right.effective, kind: left.kind)
        case (.scalar, .unit), (.scalar, .currency):
            return fail("Division by a unit value is not supported.")
        case (.unit(let lhs), .unit(let rhs)):
            guard lhs.category == rhs.category else {
                return fail(
                    "Cannot divide \(lhs.category.displayName) by \(rhs.category.displayName).")
            }
            guard lhs.category != .temperature else {
                return fail("Division of temperature values is not supported.")
            }
            let numerator = left.amount * lhs.factor
            let denominator = right.amount * rhs.factor
            return finiteDivision(numerator, denominator, kind: .scalar)
        case (.currency(let lhs), .currency(let rhs)):
            guard let denominator = convertedCurrency(right.amount, from: rhs, to: lhs)
            else { return nil }
            return finiteDivision(left.amount, denominator, kind: .scalar)
        case (.unit(let lhs), .currency):
            return fail("Cannot divide \(lhs.category.displayName) by Currency.")
        case (.currency, .unit(let rhs)):
            return fail("Cannot divide Currency by \(rhs.category.displayName).")
        }
    }

    private func finiteDivision(
        _ numerator: Double, _ denominator: Double, kind: QuantityValue.Kind
    ) -> QuantityValue? {
        let output = numerator / denominator
        return output.isFinite ? QuantityValue(amount: output, kind: kind) : nil
    }

    private mutating func parseOperand() -> QuantityValue? {
        guard var value = parsePrefix() else { return nil }
        while true {
            switch current {
            case .ident(let name):
                guard isScalar(value.kind), !value.isPercent,
                    let kind = dimension(named: name)
                else { return value }
                value.kind = kind
                dimensionCount += 1
                position += 1
            case .op("%"):
                guard isScalar(value.kind), !value.isPercent else { return nil }
                value.isPercent = true
                position += 1
            case .op("!"):
                guard isScalar(value.kind), !value.isPercent,
                    let factorial = CalcParser.factorial(value.amount)
                else { return nil }
                value.amount = factorial
                position += 1
            default:
                return value
            }
        }
    }

    private mutating func parsePrefix() -> QuantityValue? {
        switch current {
        case .number(let value), .compactNumber(let value):
            position += 1
            return QuantityValue(amount: value, kind: .scalar)
        case .intLiteral(let value, _):
            position += 1
            return QuantityValue(amount: Double(value), kind: .scalar)
        case .op("-"):
            position += 1
            guard let value = parseExpression(minBindingPower: Self.unaryBindingPower)
            else { return nil }
            return QuantityValue(amount: -value.effective, kind: value.kind)
        case .op("+"):
            position += 1
            return parseExpression(minBindingPower: Self.unaryBindingPower)
        case .op("("):
            position += 1
            guard let value = parseExpression(minBindingPower: 0),
                case .op(")") = current
            else { return nil }
            position += 1
            return value
        case .ident(let name):
            guard currencyEnabled, CalcUnits.byName[name] == nil,
                let definition = CalcCurrency.byName[name],
                let amount = number(at: position + 1)
            else { return nil }
            position += 2
            recordCurrency(definition.code)
            dimensionCount += 1
            return QuantityValue(amount: amount, kind: .currency(definition))
        default:
            return nil
        }
    }

    private mutating func dimension(named name: String) -> QuantityValue.Kind? {
        if let unit = CalcUnits.byName[name] {
            return .unit(unit)
        }
        guard currencyEnabled, let definition = CalcCurrency.byName[name] else { return nil }
        recordCurrency(definition.code)
        return .currency(definition)
    }

    private mutating func convertedCurrency(
        _ amount: Double, from: CurrencyDef, to: CurrencyDef
    ) -> Double? {
        recordCurrency(from.code)
        recordCurrency(to.code)
        guard case .on(let rates) = currency else { return nil }
        guard let rates else {
            issue = "Exchange rates unavailable — check your connection."
            return nil
        }
        guard rates.rate(for: from.code) != nil else {
            issue = "No exchange rate for \(from.code)."
            return nil
        }
        guard rates.rate(for: to.code) != nil else {
            issue = "No exchange rate for \(to.code)."
            return nil
        }
        return rates.convert(amount, from: from.code, to: to.code)
    }

    private mutating func recordCurrency(_ code: String) {
        usedCurrency = true
        if !currencyCodes.contains(code) { currencyCodes.append(code) }
    }

    private func number(at index: Int) -> Double? {
        guard index < tokens.count else { return nil }
        return CalcQuantity.numberValue(tokens[index])
    }

    private func startsQuantity(_ token: CalcToken?) -> Bool {
        switch token {
        case .number, .compactNumber, .intLiteral:
            return true
        case .ident(let name):
            return currencyEnabled && CalcUnits.byName[name] == nil
                && CalcCurrency.byName[name] != nil
                && number(at: position + 1) != nil
        default:
            return false
        }
    }

    private func isScalar(_ kind: QuantityValue.Kind) -> Bool {
        if case .scalar = kind { return true }
        return false
    }

    private mutating func fail(_ message: String) -> QuantityValue? {
        issue = message
        return nil
    }
}
