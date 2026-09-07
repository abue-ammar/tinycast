import Foundation

struct CalcExpressionParser {
    static func scalar(_ tokens: [CalcToken]) -> Double? {
        var parser = CalcExpressionParser(tokens: tokens, rates: nil)
        guard let value = parser.parse(), case .scalar = value.kind, !value.isBoolean else { return nil }
        return value.effective
    }

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

    mutating func parse() -> CalcValue? {
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

    private mutating func parseExpression(minBindingPower: Int) -> CalcValue? {
        guard var left = parseOperand(), left.effective.isFinite else { return nil }
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
                    binary.op, left, right, implicit: !binary.consumesToken), combined.effective.isFinite
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
            case .op(let next) = tokens[position + 2], next == .add || next == .subtract
        else { return nil }
        return name
    }

    /// An operator, its binding power, its right operand's minimum, and whether it consumes.
    struct BinaryOp {
        let op: CalcOperator
        let bindingPower: Int
        let rightBindingPower: Int
        let consumesToken: Bool
    }

    private func peekBinary(left: CalcValue) -> BinaryOp? {
        switch current {
        case .op(let op) where op.bindingPower != nil:
            let power = op.bindingPower ?? 0
            return BinaryOp(op: op, bindingPower: power,
                rightBindingPower: power + (op == .power ? 0 : 1), consumesToken: true)
        case .ident("mod"):
            return BinaryOp(op: .percent, bindingPower: 20, rightBindingPower: 21, consumesToken: true)
        case .ident("power"):
            return BinaryOp(op: .power, bindingPower: 30, rightBindingPower: 30, consumesToken: true)
        case .ident("xor"):
            return BinaryOp(op: .bitXor, bindingPower: 6, rightBindingPower: 7, consumesToken: true)
        case .ident("of"):
            return BinaryOp(op: .multiply, bindingPower: 20, rightBindingPower: 21, consumesToken: true)
        default:
            if case .op(.open) = current {
                return BinaryOp(op: .multiply, bindingPower: 20, rightBindingPower: 21, consumesToken: false)
            }
            if case .ident(let name) = current,
                CalcMath.constants[name] != nil || CalcMath.isFunction(name)
                    || ((name == "square" || name == "cube") && position + 1 < tokens.count
                        && tokens[position + 1] == .ident("root"))
            {
                return BinaryOp(op: .multiply, bindingPower: 20, rightBindingPower: 21, consumesToken: false)
            }
            if !isScalar(left.kind), startsQuantity(current) {
                return BinaryOp(
                    op: .add, bindingPower: Self.compositeBindingPower,
                    rightBindingPower: Self.compositeBindingPower + 1, consumesToken: false)
            }
            return nil
        }
    }

    private mutating func apply(
        _ op: CalcOperator, _ left: CalcValue, _ right: CalcValue, implicit: Bool
    ) -> CalcValue? {
        guard !left.isBoolean, !right.isBoolean else { return nil }
        switch op {
        case .equal, .notEqual, .less, .greater, .lessEqual, .greaterEqual:
            guard let amount = comparable(right, to: left), amount.isFinite else { return nil }
            let result: Bool
            switch op {
            case .equal: result = left.effective == amount
            case .notEqual: result = left.effective != amount
            case .less: result = left.effective < amount
            case .greater: result = left.effective > amount
            case .lessEqual: result = left.effective <= amount
            default: result = left.effective >= amount
            }
            return CalcValue(amount: result ? 1 : 0, kind: .scalar, isBoolean: true)
        case .percent:
            guard isScalar(left.kind), isScalar(right.kind) else { return nil }
            return CalcValue(amount: left.effective.truncatingRemainder(dividingBy: right.effective), kind: .scalar)
        case .bitAnd, .bitOr, .bitXor, .shiftLeft, .shiftRight:
            guard isScalar(left.kind), isScalar(right.kind),
                let result = CalcMath.bitwise(op, left.effective, right.effective) else { return nil }
            return CalcValue(amount: result, kind: .scalar)
        case .add, .subtract:
            return addOrSubtract(op, left, right, implicit: implicit)
        case .multiply:
            return multiply(left, right)
        case .divide:
            return divide(left, right)
        case .power:
            guard isScalar(right.kind) else { return nil }
            return power(left, exponent: right.effective)
        default:
            return nil
        }
    }

    private mutating func addOrSubtract(
        _ op: CalcOperator, _ left: CalcValue, _ right: CalcValue, implicit: Bool
    ) -> CalcValue? {
        let direction = op == .add ? 1.0 : -1.0
        if right.isPercent {
            let output = left.effective * (1 + direction * right.amount / 100)
            return CalcValue(amount: output, kind: left.kind)
        }

        switch (left.kind, right.kind) {
        case (.scalar, .scalar):
            return CalcValue(
                amount: left.effective + direction * right.effective, kind: .scalar)
        case (.unit(let lhs), .unit(let rhs)):
            guard lhs.isCompatible(with: rhs) else {
                return fail(
                    "Cannot \(op == .add ? "add" : "subtract") \(lhs.category.displayName) and \(rhs.category.displayName)."
                )
            }
            if lhs.category == .temperature, lhs.symbol != rhs.symbol {
                return fail("Cannot combine temperatures with different units.")
            }
            // Composite ("5 feet 3 inches") answers in its leading unit; `+`/`-` in the last.
            if implicit {
                guard let converted = convertedMeasurement(right.amount, from: rhs, to: lhs) else { return nil }
                return CalcValue(
                    amount: left.amount + direction * converted, kind: .unit(lhs))
            }
            guard let converted = convertedMeasurement(left.amount, from: lhs, to: rhs) else { return nil }
            return CalcValue(
                amount: converted + direction * right.amount, kind: .unit(rhs))
        case (.currency(let lhs), .currency(let rhs)):
            if implicit {
                guard let converted = convertedCurrency(right.amount, from: rhs, to: lhs)
                else { return nil }
                return CalcValue(
                    amount: left.amount + direction * converted, kind: .currency(lhs))
            }
            guard let converted = convertedCurrency(left.amount, from: lhs, to: rhs)
            else { return nil }
            return CalcValue(
                amount: converted + direction * right.amount, kind: .currency(rhs))
        case (.unit(let lhs), .currency):
            return fail(
                "Cannot \(op == .add ? "add" : "subtract") \(lhs.category.displayName) and Currency."
            )
        case (.currency, .unit(let rhs)):
            return fail(
                "Cannot \(op == .add ? "add" : "subtract") Currency and \(rhs.category.displayName)."
            )
        // A bare number takes the unit beside it; adjacency stays silent, being a half-typed unit.
        case (.unit, .scalar), (.currency, .scalar):
            guard !implicit else { return nil }
            return CalcValue(
                amount: left.amount + direction * right.effective, kind: left.kind)
        case (.scalar, .unit), (.scalar, .currency):
            guard !implicit else { return nil }
            return CalcValue(
                amount: left.effective + direction * right.amount, kind: right.kind)
        }
    }

    private mutating func multiply(
        _ left: CalcValue, _ right: CalcValue
    ) -> CalcValue? {
        switch (left.kind, right.kind) {
        case (.scalar, .scalar):
            return CalcValue(amount: left.effective * right.effective, kind: .scalar)
        case (.scalar, _):
            return CalcValue(
                amount: left.effective * right.effective, kind: right.kind)
        case (_, .scalar):
            return CalcValue(
                amount: left.effective * right.effective, kind: left.kind)
        case (.unit, .unit), (.unit, .currency), (.currency, .unit):
            return combine(left, right, dividing: false)
        default:
            return fail("Multiplication of these unit values is not supported.")
        }
    }

    private mutating func divide(
        _ left: CalcValue, _ right: CalcValue
    ) -> CalcValue? {
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

    private func arithmeticUnit(_ kind: CalcValue.Kind) -> UnitDef? {
        switch kind {
        case .unit(let unit): return unit
        case .currency(let currency): return CalcUnitExpression.named(currency.code.lowercased())
        case .scalar: return nil
        }
    }

    private mutating func combine(_ left: CalcValue, _ right: CalcValue, dividing: Bool) -> CalcValue? {
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

    private func derived(_ amount: Double, dimension: CalcDimension, unit: UnitDef? = nil) -> CalcValue? {
        guard amount.isFinite else { return nil }
        if dimension == .scalar { return CalcValue(amount: amount, kind: .scalar) }
        guard let unit = unit ?? CalcUnits.baseUnits[dimension] else { return nil }
        if dimension == CalcDimension(currency: 1), let currency = unit.currency {
            return CalcValue(amount: amount, kind: .currency(currency))
        }
        let output = amount / unit.factor
        return output.isFinite ? CalcValue(amount: output, kind: .unit(unit)) : nil
    }

    private func power(_ value: CalcValue, exponent: Double) -> CalcValue? {
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
        _ numerator: Double, _ denominator: Double, kind: CalcValue.Kind
    ) -> CalcValue? {
        let output = numerator / denominator
        return output.isFinite ? CalcValue(amount: output, kind: kind) : nil
    }

    private mutating func parseOperand() -> CalcValue? {
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
            case .op(let op) where op == .multiply || op == .divide:
                guard case .ident? = position + 1 < tokens.count ? tokens[position + 1] : nil,
                    let unit = arithmeticUnit(value.kind),
                    let next = CalcUnitExpression.factor(tokens, at: position + 1),
                    next.end == tokens.count || CalcQuantity.numberValue(tokens[next.end]) == nil,
                    let combined = CalcUnitExpression.combine(unit, next.unit, dividing: op == .divide) else { return value }
                value.kind = .unit(combined)
                if combined.currency != nil { usedCurrencyRate = true }
                dimensionCount += 1
                position = next.end
            case .op(.percent):
                guard isScalar(value.kind), !value.isPercent, !value.isBoolean else { return nil }
                value.isPercent = true
                position += 1
            case .op(.factorial):
                guard isScalar(value.kind), !value.isPercent, !value.isBoolean,
                    let factorial = CalcMath.factorial(value.amount)
                else { return nil }
                value.amount = factorial
                position += 1
            default:
                return value
            }
        }
    }

    private mutating func parsePrefix() -> CalcValue? {
        switch current {
        case .number(let value), .compactNumber(let value):
            position += 1
            return CalcValue(amount: value, kind: .scalar)
        case .intLiteral(let value, _):
            position += 1
            return CalcValue(amount: Double(value), kind: .scalar)
        case .op(.bitNot):
            position += 1
            guard let value = parseExpression(minBindingPower: Self.unaryBindingPower),
                isScalar(value.kind), !value.isBoolean,
                let result = CalcMath.bitwise(.bitNot, value.effective) else { return nil }
            return CalcValue(amount: result, kind: .scalar)
        case .op(.subtract):
            position += 1
            guard let value = parseExpression(minBindingPower: Self.unaryBindingPower), !value.isBoolean
            else { return nil }
            return CalcValue(amount: -value.effective, kind: value.kind)
        case .op(.add):
            position += 1
            guard let value = parseExpression(minBindingPower: Self.unaryBindingPower), !value.isBoolean else { return nil }
            return value
        case .op(.open):
            return parseGrouped()
        case .ident(let name):
            if name == "square" || name == "cube", position + 1 < tokens.count,
                tokens[position + 1] == .ident("root") {
                position += 2
                if current == .ident("of") { position += 1 }
                guard let value = parseOperand(), !value.isBoolean else { return nil }
                operationCount += 1
                if name == "square" { return power(value, exponent: 0.5) }
                guard let result = power(CalcValue(amount: abs(value.effective), kind: value.kind), exponent: 1.0 / 3)
                else { return nil }
                return CalcValue(amount: value.amount < 0 ? -result.amount : result.amount, kind: result.kind)
            }
            if let constant = CalcMath.constants[name] {
                position += 1
                return CalcValue(amount: constant, kind: .scalar)
            }
            if CalcMath.multipleArguments.contains(name), position + 1 < tokens.count, tokens[position + 1] == .op(.open) {
                return parseFunction(name)
            }
            if let function = CalcMath.functions[name] {
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
                        CalcValue(amount: abs(argument.amount), kind: argument.kind), exponent: 1.0 / 3)
                    else { return nil }
                    return CalcValue(amount: argument.amount < 0 ? -result.amount : result.amount, kind: result.kind)
                }
                if ["abs", "floor", "ceil", "round", "trunc"].contains(name) {
                    return CalcValue(amount: function(argument.amount), kind: argument.kind)
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
            return CalcValue(amount: amount, kind: .currency(definition))
        default:
            return nil
        }
    }

    private mutating func comparable(_ value: CalcValue, to reference: CalcValue) -> Double? {
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

    private mutating func parseFunction(_ name: String) -> CalcValue? {
        position += 2
        var values: [CalcValue] = []
        while true {
            guard let value = parseExpression(minBindingPower: 0), !value.isBoolean else { return nil }
            values.append(value)
            if current == .op(.close) { position += 1; break }
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
        return CalcValue(amount: result, kind: keepsUnit ? first.kind : .scalar)
    }

    /// A group is its own conversion scope, so `(20 sgd to usd) * 30` converts then multiplies.
    private mutating func parseGrouped() -> CalcValue? {
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
    private mutating func parseGroupedValue(upTo end: Int) -> CalcValue? {
        if end - position == 1, case .ident(let name) = tokens[position],
            let kind = dimension(named: name)
        {
            position = end
            dimensionCount += 1
            return CalcValue(amount: 1, kind: kind)
        }
        if position < end, case .ident = tokens[position],
            let unit = CalcUnitExpression.parse(Array(tokens[position..<end])) {
            position = end
            dimensionCount += 1
            if unit.currency != nil { usedCurrencyRate = true }
            return CalcValue(amount: 1, kind: .unit(unit))
        }
        guard let value = parseExpression(minBindingPower: 0), position == end else { return nil }
        return value
    }

    private func matchingParenthesis() -> Int? {
        guard case .op(.open)? = current else { return nil }
        var depth = 0
        for index in position..<tokens.count {
            if case .op(.open) = tokens[index] { depth += 1 }
            if case .op(.close) = tokens[index] {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return nil
    }

    mutating func converted(
        _ value: CalcValue, to targetName: String
    ) -> CalcValue? {
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
                return CalcValue(amount: output, kind: .unit(to))
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
                return CalcValue(amount: output, kind: .currency(to))
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

    private mutating func dimension(named name: String) -> CalcValue.Kind? {
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

    private func isScalar(_ kind: CalcValue.Kind) -> Bool {
        if case .scalar = kind { return true }
        return false
    }

    private mutating func fail(_ message: String) -> CalcValue? {
        issue = message
        return nil
    }
}
