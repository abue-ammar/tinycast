import Foundation

/// Pixels against physical size: `3000 px to inches at 300 ppi`, `ppi of 27 inch display at 3840x2160`.
enum CalcPixelDensity {
    static func evaluate(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard let at = tokens.lastIndex(where: { $0 == .ident("at") || $0 == .ident("with") }), at > 0 else {
            return nil
        }
        return converted(tokens, at: at, query: query) ?? displayDensity(tokens, at: at, query: query)
    }

    private static func grouped(_ tokens: ArraySlice<CalcToken>) -> [CalcToken] {
        [.op(.open)] + tokens + [.op(.close)]
    }

    /// `<amount> to <unit> at <density>`: pixels divide by the density, and lengths multiply by it.
    private static func converted(_ tokens: [CalcToken], at: Int, query: String) -> CalcResult? {
        let connector = at - 2
        guard connector > 0, CalcUnits.isConnector(tokens[connector]), case .ident = tokens[at - 1],
            let density = CalcExpressionParser.value(Array(tokens[(at + 1)...])),
            case .unit(let densityUnit) = density.kind, densityUnit.category == .pixelDensity,
            let source = CalcExpressionParser.value(Array(tokens[..<connector])),
            case .unit(let sourceUnit) = source.kind
        else { return nil }
        let op: CalcOperator
        switch sourceUnit.category {
        case .pixels: op = .divide
        case .length: op = .multiply
        default: return nil
        }
        let expression =
            grouped(tokens[..<connector]) + [.op(op)] + grouped(tokens[(at + 1)...]) + tokens[connector..<at]
        return CalcQuantity.evaluate(expression, query: query, rates: nil)
    }

    private static let screenWords: [CalcToken] = [
        .ident("display"), .ident("screen"), .ident("monitor"), .ident("device")
    ]

    private static func displayDensity(_ tokens: [CalcToken], at: Int, query: String) -> CalcResult? {
        guard at > 2, tokens[0] == .ident("ppi") || tokens[0] == .ident("density"), tokens[1] == .ident("of"),
            tokens.count == at + 4, let width = CalcQuantity.numberValue(tokens[at + 1]),
            tokens[at + 2] == .op(.multiply) || tokens[at + 2] == .ident("x"),
            let height = CalcQuantity.numberValue(tokens[at + 3]), let ppi = CalcUnits.byName["ppi"],
            let inch = CalcUnits.byName["in"]
        else { return nil }
        var size = tokens[2..<at]
        if let last = size.last, screenWords.contains(last) { size.removeLast() }
        guard let diagonal = CalcExpressionParser.value(Array(size)) else { return nil }
        let inches: Double
        switch diagonal.kind {
        case .scalar: inches = diagonal.amount
        case .unit(let unit) where unit.category == .length:
            inches = diagonal.amount * unit.factor / inch.factor
        default: return nil
        }
        let density = (width * width + height * height).squareRoot() / inches
        guard inches > 0, density.isFinite else { return nil }
        return .phrase(query, .measurement(density, unit: ppi), target: ppi.name)
    }
}
