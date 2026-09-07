import Foundation

enum CalcUnitExpression {
    static func named(_ name: String) -> UnitDef? {
        if let unit = CalcUnits.byName[name] { return unit }
        guard let currency = CalcCurrency.byName[name] else { return nil }
        return UnitDef(currency.code, currency.name, .compound, 1,
            dimension: CalcDimension(currency: 1), currency: currency)
    }

    static func parse(_ tokens: [CalcToken]) -> UnitDef? {
        var parser = UnitParser(tokens: tokens)
        guard let unit = parser.expression(), parser.index == tokens.count else { return nil }
        return unit
    }

    static func factor(_ tokens: [CalcToken], at index: Int) -> (unit: UnitDef, end: Int)? {
        var parser = UnitParser(tokens: tokens, index: index)
        guard let unit = parser.factor() else { return nil }
        return (unit, parser.index)
    }

    static func combine(_ left: UnitDef, _ right: UnitDef, dividing: Bool) -> UnitDef? {
        guard let lhs = left.dimension, let rhs = right.dimension,
            left.currency == nil || right.currency == nil || left.currency == right.currency
        else { return nil }
        let dimension = lhs.adding(rhs, scale: dividing ? -1 : 1)
        guard abs(dimension.currency) <= 1 else { return nil }
        let factor = dividing ? left.factor / right.factor : left.factor * right.factor
        guard factor.isFinite, factor > 0 else { return nil }
        let rightSymbol = dividing && (right.symbol.contains("/") || right.symbol.contains("·"))
            ? "(\(right.symbol))" : right.symbol
        return UnitDef(left.symbol + (dividing ? "/" : "·") + rightSymbol,
            "Compound Units", .compound, factor, dimension: dimension,
            currency: dimension.currency == 0 ? nil : left.currency ?? right.currency)
    }

    static func power(_ unit: UnitDef, _ exponent: Double) -> UnitDef? {
        guard let dimension = unit.dimension else { return nil }
        let raised = dimension.raised(to: exponent)
        guard abs(raised.currency) <= 1, raised.currency.rounded() == raised.currency else { return nil }
        let factor = pow(unit.factor, exponent)
        guard factor.isFinite, factor > 0 else { return nil }
        let symbol = unit.symbol.contains("/") || unit.symbol.contains("·") ? "(\(unit.symbol))" : unit.symbol
        let suffix = exponent == 2 ? "²" : exponent == 3 ? "³" : "^" + CalcFormatter.copyText(exponent)
        return UnitDef(symbol + suffix, "Compound Units", .compound, factor, dimension: raised,
            currency: raised.currency == 0 ? nil : unit.currency)
    }

    private struct UnitParser {
        let tokens: [CalcToken]
        var index = 0
        var current: CalcToken? { index < tokens.count ? tokens[index] : nil }

        mutating func expression() -> UnitDef? {
            guard var left = factor() else { return nil }
            while current == .op(.multiply) || current == .op(.divide) {
                let dividing = current == .op(.divide)
                index += 1
                guard let right = factor(), let result = combine(left, right, dividing: dividing) else { return nil }
                left = result
            }
            return left
        }

        mutating func factor() -> UnitDef? {
            let unit: UnitDef
            if case .ident(let name) = current, let found = named(name) {
                unit = found
                index += 1
            } else if current == .op(.open) {
                index += 1
                guard let found = expression(), current == .op(.close) else { return nil }
                unit = found
                index += 1
            } else { return nil }
            guard current == .op(.power) else { return unit }
            index += 1
            let negative = current == .op(.subtract)
            if negative { index += 1 }
            guard case .number(let number) = current, number <= 16 else { return nil }
            index += 1
            return power(unit, negative ? -number : number)
        }
    }
}
