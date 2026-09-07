import Foundation

/// Typed arithmetic for measurements and currencies.
enum CalcQuantity {
    static func evaluate(
        _ tokens: [CalcToken], query: String, rates: CurrencyRates?, region: String? = nil,
        preserveStandaloneUnit: Bool = false
    ) -> CalcResult? {
        let split = splitConversion(tokens)
        if let target = split.targetName, target != "timespan", target != "duration",
            isSimpleConversionSource(split.expressionTokens),
            CalcUnits.byName[target] != nil || CalcCurrency.byName[target] != nil {
            return nil
        }

        var parser = QuantityParser(tokens: split.expressionTokens, rates: rates)
        guard let value = parser.parse() else {
            guard let message = parser.issue else { return nil }
            return CalcResult(expression: query, payload: .error(message: message))
        }
        if parser.dimensionCount == 0, !value.isBoolean {
            guard split.targetName == nil, parser.operationCount > 0 else { return nil }
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
        _ value: QuantityValue, expression: String
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

    fileprivate static func convertUnit(_ amount: Double, from: UnitDef, to: UnitDef) -> Double {
        (amount * from.factor + from.offset - to.offset) / to.factor
    }

    private static func splitConversion(
        _ tokens: [CalcToken]
    ) -> (expressionTokens: [CalcToken], targetName: String?) {
        guard let target = conversionTarget(tokens, from: 0, to: tokens.count) else { return (tokens, nil) }
        return (Array(tokens[..<target.start]), target.name)
    }

    fileprivate static func conversionTarget(
        _ tokens: [CalcToken], from start: Int, to end: Int
    ) -> (start: Int, name: String)? {
        var depth = 0
        for index in start..<end {
            if tokens[index] == .op("(") { depth += 1 }
            if tokens[index] == .op(")") { depth -= 1 }
            guard depth == 0, index + 1 < end, CalcUnits.isConnector(tokens[index]) else { continue }
            if index + 2 == end, case .ident(let name) = tokens[index + 1] { return (index, name) }
            let target = Array(tokens[(index + 1)..<end])
            guard CalcUnitExpression.parse(target) != nil else { continue }
            return (index, target.map { token in
                switch token {
                case .ident(let name): return name
                case .op(let op): return String(op)
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
                add(CalcMath.operatorText(op))
                if op == "-" || op == "+" { attachNext = isSign(at: index, tokens) }
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
    var isBoolean = false

    var effective: Double {
        isPercent ? amount / 100 : amount
    }
}

private struct QuantityParser {
    let tokens: [CalcToken]
    let rates: CurrencyRates?
    var position = 0
    var operationCount = 0
    var dimensionCount = 0
    var usedCurrency = false
    var usedCurrencyRate = false
    var currencyCodes: [String] = []
    var issue: String?

    private static let unaryBindingPower = 25
    private static let compositeBindingPower = 40

    private var current: CalcToken? {
        position < tokens.count ? tokens[position] : nil
    }

    mutating func parse() -> QuantityValue? {
        guard var value = parseExpression(minBindingPower: 0), position == tokens.count,
            value.effective.isFinite
        else { return nil }
        if case .unit(let unit) = value.kind, unit.category == .compound,
            let dimension = unit.dimension, dimension == .scalar || dimension == CalcDimension(currency: 1),
            let simplified = derived(value.effective * unit.factor, dimension: dimension, unit: unit) {
            value = simplified
            operationCount += 1
        }
        return value
    }

    private mutating func parseExpression(minBindingPower: Int) -> QuantityValue? {
        guard var left = parseOperand() else { return nil }
        if let target = peekAdditiveConversion() {
            position += 2
            operationCount += 1
            guard let converted = converted(left, to: target) else { return nil }
            left = converted
        }
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

    /// A mid-expression `to` only when `+`/`-` follows it: `to usd * 30` stays genuinely ambiguous.
    private func peekAdditiveConversion() -> String? {
        guard position + 2 < tokens.count, CalcUnits.isConnector(tokens[position]),
            case .ident(let name) = tokens[position + 1],
            CalcUnits.byName[name] != nil || CalcCurrency.byName[name] != nil,
            case .op(let next) = tokens[position + 2], next == "+" || next == "-"
        else { return nil }
        return name
    }

    /// An operator, its binding power, its right operand's minimum, and whether it consumes.
    struct BinaryOp {
        let op: Character
        let bindingPower: Int
        let rightBindingPower: Int
        let consumesToken: Bool
    }

    private func peekBinary(left: QuantityValue) -> BinaryOp? {
        switch current {
        case .op(let op) where CalcMath.bindingPower(op) != nil:
            let power = CalcMath.bindingPower(op) ?? 0
            return BinaryOp(op: op, bindingPower: power,
                rightBindingPower: power + (op == "^" ? 0 : 1), consumesToken: true)
        case .ident("mod"):
            return BinaryOp(op: "%", bindingPower: 20, rightBindingPower: 21, consumesToken: true)
        case .ident("power"):
            return BinaryOp(op: "^", bindingPower: 30, rightBindingPower: 30, consumesToken: true)
        case .ident("xor"):
            return BinaryOp(op: "⊻", bindingPower: 6, rightBindingPower: 7, consumesToken: true)
        case .ident("of"):
            return BinaryOp(op: "*", bindingPower: 20, rightBindingPower: 21, consumesToken: true)
        default:
            // Juxtaposition against a bracket multiplies, matching the scalar parser.
            if case .op("(") = current {
                return BinaryOp(op: "*", bindingPower: 20, rightBindingPower: 21, consumesToken: false)
            }
            if case .ident(let name) = current,
                CalcParser.constants[name] != nil || CalcMath.isFunction(name)
            {
                return BinaryOp(op: "*", bindingPower: 20, rightBindingPower: 21, consumesToken: false)
            }
            if !isScalar(left.kind), startsQuantity(current) {
                return BinaryOp(
                    op: "+", bindingPower: Self.compositeBindingPower,
                    rightBindingPower: Self.compositeBindingPower + 1, consumesToken: false)
            }
            return nil
        }
    }

    private mutating func apply(
        _ op: Character, _ left: QuantityValue, _ right: QuantityValue, implicit: Bool
    ) -> QuantityValue? {
        guard !left.isBoolean, !right.isBoolean else { return nil }
        switch op {
        case "≡", "≠", "<", ">", "≤", "≥":
            guard let amount = comparable(right, to: left) else { return nil }
            let result: Bool
            switch op {
            case "≡": result = left.effective == amount
            case "≠": result = left.effective != amount
            case "<": result = left.effective < amount
            case ">": result = left.effective > amount
            case "≤": result = left.effective <= amount
            default: result = left.effective >= amount
            }
            return QuantityValue(amount: result ? 1 : 0, kind: .scalar, isBoolean: true)
        case "%":
            guard isScalar(left.kind), isScalar(right.kind) else { return nil }
            return QuantityValue(amount: left.effective.truncatingRemainder(dividingBy: right.effective), kind: .scalar)
        case "&", "|", "⊻", "«", "»":
            guard isScalar(left.kind), isScalar(right.kind),
                let result = CalcMath.bitwise(op, left.effective, right.effective) else { return nil }
            return QuantityValue(amount: result, kind: .scalar)
        case "+", "-":
            return addOrSubtract(op, left, right, implicit: implicit)
        case "*":
            return multiply(left, right)
        case "/":
            return divide(left, right)
        case "^":
            guard isScalar(right.kind) else { return nil }
            return power(left, exponent: right.effective)
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
            guard lhs.isCompatible(with: rhs) else {
                return fail(
                    "Cannot \(op == "+" ? "add" : "subtract") \(lhs.category.displayName) and \(rhs.category.displayName)."
                )
            }
            if lhs.category == .temperature, lhs.symbol != rhs.symbol {
                return fail("Cannot combine temperatures with different units.")
            }
            // Composite ("5 feet 3 inches") answers in its leading unit; `+`/`-` in the last.
            if implicit {
                guard let converted = convertedMeasurement(right.amount, from: rhs, to: lhs) else { return nil }
                return QuantityValue(
                    amount: left.amount + direction * converted, kind: .unit(lhs))
            }
            guard let converted = convertedMeasurement(left.amount, from: lhs, to: rhs) else { return nil }
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
        // A bare number takes the unit beside it; adjacency stays silent, being a half-typed unit.
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
        case (.unit, .unit), (.unit, .currency), (.currency, .unit):
            return combine(left, right, dividing: false)
        default:
            return fail("Multiplication of these unit values is not supported.")
        }
    }

    private mutating func divide(
        _ left: QuantityValue, _ right: QuantityValue
    ) -> QuantityValue? {
        guard right.effective != 0 else { return nil }
        switch (left.kind, right.kind) {
        case (.scalar, .scalar):
            return finiteDivision(left.effective, right.effective, kind: .scalar)
        case (.unit, .scalar), (.currency, .scalar):
            return finiteDivision(left.effective, right.effective, kind: left.kind)
        case (.scalar, .unit), (.scalar, .currency):
            guard let unit = arithmeticUnit(right.kind), let inverted = CalcUnitExpression.power(unit, -1),
                let dimension = inverted.dimension else { return nil }
            if inverted.currency != nil { usedCurrencyRate = true }
            return derived(left.effective / (right.effective * unit.factor), dimension: dimension,
                unit: CalcUnits.baseUnits[dimension] ?? inverted)
        case (.unit(let lhs), .unit(let rhs)):
            if !lhs.isCompatible(with: rhs) || lhs.currency != nil || rhs.currency != nil {
                return combine(left, right, dividing: true)
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
        case (.unit, .currency), (.currency, .unit):
            return combine(left, right, dividing: true)
        }
    }

    private func arithmeticUnit(_ kind: QuantityValue.Kind) -> UnitDef? {
        switch kind {
        case .unit(let unit): return unit
        case .currency(let currency): return CalcUnitExpression.named(currency.code.lowercased())
        case .scalar: return nil
        }
    }

    private mutating func combine(_ left: QuantityValue, _ right: QuantityValue, dividing: Bool) -> QuantityValue? {
        guard let lhs = arithmeticUnit(left.kind), var rhs = arithmeticUnit(right.kind) else { return nil }
        if lhs.currency == nil, rhs.currency == nil, let leftDimension = lhs.dimension, let rightDimension = rhs.dimension {
            let dimension = leftDimension.adding(rightDimension, scale: dividing ? -1 : 1)
            let unit = (dividing ? nil : CalcUnits.productUnit(lhs, rhs)) ?? CalcUnits.baseUnits[dimension]
            if dimension == .scalar || unit != nil {
                let amount = dividing ? left.effective * lhs.factor / (right.effective * rhs.factor)
                    : left.effective * lhs.factor * right.effective * rhs.factor
                return derived(amount, dimension: dimension, unit: unit)
            }
        }
        var amount = right.effective
        if let source = rhs.currency, let target = lhs.currency, source != target {
            guard let factor = convertedCurrency(1, from: source, to: target), let dimension = rhs.dimension
            else { return nil }
            amount *= pow(factor, dimension.currency)
            rhs = UnitDef(rhs.symbol.replacingOccurrences(of: source.code, with: target.code), rhs.name,
                rhs.category, rhs.factor, dimension: dimension, currency: target)
        }
        guard let combined = CalcUnitExpression.combine(lhs, rhs, dividing: dividing),
            let dimension = combined.dimension else {
            return fail("Multiplication of these unit values is not supported.")
        }
        if lhs.currency != nil || rhs.currency != nil { usedCurrencyRate = true }
        let base = dividing ? left.effective * lhs.factor / (amount * rhs.factor)
            : left.effective * lhs.factor * amount * rhs.factor
        let preferred = dividing ? nil : CalcUnits.productUnit(lhs, rhs)
        return derived(base, dimension: dimension, unit: preferred ?? CalcUnits.baseUnits[dimension] ?? combined)
    }

    private func derived(_ amount: Double, dimension: CalcDimension, unit: UnitDef? = nil) -> QuantityValue? {
        guard amount.isFinite else { return nil }
        if dimension == .scalar { return QuantityValue(amount: amount, kind: .scalar) }
        guard let unit = unit ?? CalcUnits.baseUnits[dimension] else { return nil }
        if dimension == CalcDimension(currency: 1), let currency = unit.currency {
            return QuantityValue(amount: amount, kind: .currency(currency))
        }
        let output = amount / unit.factor
        return output.isFinite ? QuantityValue(amount: output, kind: .unit(unit)) : nil
    }

    private func power(_ value: QuantityValue, exponent: Double) -> QuantityValue? {
        switch value.kind {
        case .scalar:
            return derived(pow(value.effective, exponent), dimension: .scalar)
        case .unit(let unit):
            guard let dimension = unit.dimension else { return nil }
            let raised = dimension.raised(to: exponent)
            return derived(pow(value.amount * unit.factor, exponent), dimension: raised,
                unit: CalcUnits.baseUnits[raised] ?? CalcUnitExpression.power(unit, exponent))
        case .currency:
            return nil
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
                guard isScalar(value.kind), !value.isPercent, !value.isBoolean,
                    let kind = dimension(named: name)
                else { return value }
                value.kind = kind
                dimensionCount += 1
                position += 1
            case .op(let op) where op == "*" || op == "/":
                guard case .ident? = position + 1 < tokens.count ? tokens[position + 1] : nil,
                    let unit = arithmeticUnit(value.kind),
                    let next = CalcUnitExpression.factor(tokens, at: position + 1),
                    next.end == tokens.count || CalcQuantity.numberValue(tokens[next.end]) == nil,
                    let combined = CalcUnitExpression.combine(unit, next.unit, dividing: op == "/") else { return value }
                value.kind = .unit(combined)
                if combined.currency != nil { usedCurrencyRate = true }
                dimensionCount += 1
                position = next.end
            case .op("%"):
                guard isScalar(value.kind), !value.isPercent, !value.isBoolean else { return nil }
                value.isPercent = true
                position += 1
            case .op("!"):
                guard isScalar(value.kind), !value.isPercent, !value.isBoolean,
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
        case .op("~"):
            position += 1
            guard let value = parseExpression(minBindingPower: Self.unaryBindingPower),
                isScalar(value.kind), !value.isBoolean,
                let result = CalcMath.bitwise("~", value.effective) else { return nil }
            return QuantityValue(amount: result, kind: .scalar)
        case .op("-"):
            position += 1
            guard let value = parseExpression(minBindingPower: Self.unaryBindingPower), !value.isBoolean
            else { return nil }
            return QuantityValue(amount: -value.effective, kind: value.kind)
        case .op("+"):
            position += 1
            guard let value = parseExpression(minBindingPower: Self.unaryBindingPower), !value.isBoolean else { return nil }
            return value
        case .op("("):
            return parseGrouped()
        case .ident(let name):
            if let constant = CalcParser.constants[name] {
                position += 1
                return QuantityValue(amount: constant, kind: .scalar)
            }
            if CalcMath.multipleArguments.contains(name), position + 1 < tokens.count, tokens[position + 1] == .op("(") {
                return parseFunction(name)
            }
            if let function = CalcParser.functions[name] {
                position += 1
                guard let argument = parseOperand(), !argument.isBoolean else { return nil }
                operationCount += 1
                if isScalar(argument.kind) {
                    return derived(function(argument.effective), dimension: .scalar)
                }
                if case .unit(let unit) = argument.kind, unit.category == .angle,
                    ["sin", "cos", "tan", "cot", "sec", "csc"].contains(name)
                {
                    return derived(function(argument.amount * unit.factor), dimension: .scalar)
                }
                if name == "sqrt" { return power(argument, exponent: 0.5) }
                if name == "cbrt" {
                    guard let result = power(
                        QuantityValue(amount: abs(argument.amount), kind: argument.kind), exponent: 1.0 / 3)
                    else { return nil }
                    return QuantityValue(amount: argument.amount < 0 ? -result.amount : result.amount, kind: result.kind)
                }
                if ["abs", "floor", "ceil", "round", "trunc"].contains(name) {
                    return QuantityValue(amount: function(argument.amount), kind: argument.kind)
                }
                return nil
            }
            guard CalcUnits.byName[name] == nil,
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

    private mutating func comparable(_ value: QuantityValue, to reference: QuantityValue) -> Double? {
        guard !value.isBoolean, !reference.isBoolean else { return nil }
        switch (reference.kind, value.kind) {
        case (.scalar, .scalar): return value.effective
        case (.unit(let target), .unit(let source)):
            guard target.isCompatible(with: source) else { return failComparison() }
            return convertedMeasurement(value.effective, from: source, to: target)
        case (.currency(let target), .currency(let source)):
            return convertedCurrency(value.effective, from: source, to: target)
        default: return failComparison()
        }
    }

    private mutating func failComparison() -> Double? {
        issue = "Cannot compare values with different dimensions."
        return nil
    }

    private mutating func parseFunction(_ name: String) -> QuantityValue? {
        position += 2
        var values: [QuantityValue] = []
        while true {
            guard let value = parseExpression(minBindingPower: 0), !value.isBoolean else { return nil }
            values.append(value)
            if current == .op(")") { position += 1; break }
            guard current == .comma else { return nil }
            position += 1
        }
        operationCount += 1
        let first = values[0]
        let keepsUnit = CalcMath.measurements.contains(name)
        var amounts: [Double] = []
        for (index, value) in values.enumerated() {
            if name == "round", index == 1 {
                guard isScalar(value.kind) else { return nil }
                amounts.append(value.effective)
            } else if keepsUnit {
                guard let amount = comparable(value, to: first) else { return nil }
                amounts.append(amount)
            } else {
                guard isScalar(value.kind) else { return nil }
                amounts.append(value.effective)
            }
        }
        guard let result = CalcMath.evaluate(name, amounts) else { return nil }
        return QuantityValue(amount: result, kind: keepsUnit ? first.kind : .scalar)
    }

    /// A group is its own conversion scope, so `(20 sgd to usd) * 30` converts then multiplies.
    private mutating func parseGrouped() -> QuantityValue? {
        guard let close = matchingParenthesis() else { return nil }
        position += 1
        let target = CalcQuantity.conversionTarget(tokens, from: position, to: close)
        guard let value = parseGroupedValue(upTo: target?.start ?? close)
        else { return nil }
        position = close + 1
        guard let target else { return value }
        operationCount += 1
        return converted(value, to: target.name)
    }

    /// A lone unit or currency implies an amount of 1, the way `eur to usd` already does.
    private mutating func parseGroupedValue(upTo end: Int) -> QuantityValue? {
        if end - position == 1, case .ident(let name) = tokens[position],
            let kind = dimension(named: name)
        {
            position = end
            dimensionCount += 1
            return QuantityValue(amount: 1, kind: kind)
        }
        if position < end, case .ident = tokens[position],
            let unit = CalcUnitExpression.parse(Array(tokens[position..<end])) {
            position = end
            dimensionCount += 1
            if unit.currency != nil { usedCurrencyRate = true }
            return QuantityValue(amount: 1, kind: .unit(unit))
        }
        guard let value = parseExpression(minBindingPower: 0), position == end else { return nil }
        return value
    }

    private func matchingParenthesis() -> Int? {
        guard case .op("(")? = current else { return nil }
        var depth = 0
        for index in position..<tokens.count {
            if case .op("(") = tokens[index] { depth += 1 }
            if case .op(")") = tokens[index] {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return nil
    }

    mutating func converted(
        _ value: QuantityValue, to targetName: String
    ) -> QuantityValue? {
        switch value.kind {
        case .scalar:
            return nil
        case .unit(let from):
            if let to = CalcUnits.byName[targetName] ?? compoundTarget(targetName) {
                guard from.isCompatible(with: to) else {
                    return fail(
                        "Cannot convert \(from.category.displayName) to \(to.category.displayName).")
                }
                guard let output = convertedMeasurement(value.effective, from: from, to: to), output.isFinite
                else { return nil }
                return QuantityValue(amount: output, kind: .unit(to))
            }
            if CalcCurrency.byName[targetName] != nil {
                return fail(
                    "Cannot convert \(from.category.displayName) to \(CalcCurrency.categoryName).")
            }
            return nil
        case .currency(let from):
            if let to = CalcCurrency.byName[targetName] {
                guard let output = convertedCurrency(value.amount, from: from, to: to)
                else { return nil }
                return QuantityValue(amount: output, kind: .currency(to))
            }
            if let to = CalcUnits.byName[targetName] {
                return fail(
                    "Cannot convert \(CalcCurrency.categoryName) to \(to.category.displayName).")
            }
            return nil
        }
    }

    private func compoundTarget(_ name: String) -> UnitDef? {
        guard name.contains(" "), let tokens = CalcTokenizer.tokenize(name) else { return nil }
        return CalcUnitExpression.parse(tokens)
    }

    private mutating func convertedMeasurement(_ amount: Double, from: UnitDef, to: UnitDef) -> Double? {
        var amount = amount
        if let source = from.currency, let target = to.currency, source != target {
            guard let factor = convertedCurrency(1, from: source, to: target), let dimension = from.dimension
            else { return nil }
            amount *= pow(factor, dimension.currency)
        }
        return CalcQuantity.convertUnit(amount, from: from, to: to)
    }

    private mutating func dimension(named name: String) -> QuantityValue.Kind? {
        if let unit = CalcUnits.byName[name] {
            return .unit(unit)
        }
        guard let definition = CalcCurrency.byName[name] else { return nil }
        recordCurrency(definition.code)
        return .currency(definition)
    }

    private mutating func convertedCurrency(
        _ amount: Double, from: CurrencyDef, to: CurrencyDef
    ) -> Double? {
        recordCurrency(from.code)
        recordCurrency(to.code)
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
            return CalcUnits.byName[name] == nil && CalcCurrency.byName[name] != nil
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
