import Foundation

/// Rounding and fraction phrasings, such as `1/3 to 2 dp` and `0.75 as fraction`.
enum CalcRounding {
    static func evaluate(_ tokens: [CalcToken], query: String) -> CalcResult? {
        let mentionsRounding = tokens.contains { token in
            guard case .ident(let name) = token else { return false }
            return keywords.contains(name)
        }
        guard mentionsRounding else { return nil }
        return fraction(tokens, query: query) ?? rounded(tokens, query: query)
    }

    private static let keywords: Set<String> = [
        "round", "rounded", "nearest", "dp", "decimal", "decimals", "digits", "places", "fraction"
    ]

    // MARK: - Rounding

    private static func rounded(_ tokens: [CalcToken], query: String) -> CalcResult? {
        var rest = tokens[...]
        var rule: FloatingPointRoundingRule?
        if rest.first == .ident("round") {
            rest.removeFirst()
            rule = direction(&rest)
        }
        guard let end = rest.firstIndex(where: { $0 == .ident("rounded") || $0 == .ident("to") }),
            var value = CalcExpressionParser.value(Array(rest[..<end])), !value.isPercent
        else { return nil }
        rest = rest[end...]
        if rest.first == .ident("rounded") {
            guard rule == nil else { return nil }
            rest.removeFirst()
            rule = direction(&rest)
        }
        let precision: Precision
        if rest.isEmpty {
            guard rule != nil else { return nil }
            precision = .step(1)
        } else {
            guard rest.first == .ident("to"), let target = self.precision(Array(rest.dropFirst())) else {
                return nil
            }
            precision = target
        }
        value.amount = precision.apply(to: value.amount, rule: rule ?? .toNearestOrAwayFromZero)
        guard value.amount.isFinite else { return nil }
        return .phrase(
            query, .quantity(value), target: String(localized: "Rounded"), isCurrency: value.isCurrency)
    }

    private static func direction(_ rest: inout ArraySlice<CalcToken>) -> FloatingPointRoundingRule {
        switch rest.first {
        case .ident("up"):
            rest.removeFirst()
            return .up
        case .ident("down"):
            rest.removeFirst()
            return .down
        default:
            return .toNearestOrAwayFromZero
        }
    }

    private enum Precision {
        case step(Double)
        case decimals(Int)

        func apply(to amount: Double, rule: FloatingPointRoundingRule) -> Double {
            switch self {
            case .step(let step):
                return (amount / step).rounded(rule) * step
            case .decimals(let places):
                let scale = pow(10, Double(places))
                return (amount * scale).rounded(rule) / scale
            }
        }
    }

    /// `nearest 5`, `the nearest hundred`, `2 dp`, `3 decimal places`, `5 digits`.
    private static func precision(_ tokens: [CalcToken]) -> Precision? {
        var target = tokens[...]
        if target.first == .ident("the") { target.removeFirst() }
        if target.first == .ident("nearest") {
            target.removeFirst()
            if target.count == 1, case .ident(let name) = target.first, let step = stepWords[name] {
                return .step(step)
            }
            guard let step = CalcExpressionParser.scalar(Array(target)), step > 0 else { return nil }
            return .step(step)
        }
        guard let places = target.first.flatMap(CalcQuantity.numberValue), places.rounded() == places,
            (0...15).contains(places), placeWords.contains(Array(target.dropFirst()))
        else { return nil }
        return .decimals(Int(places))
    }

    private static let stepWords: [String: Double] = [
        "ten": 10, "hundred": 100, "thousand": 1_000, "million": 1_000_000
    ]

    private static let placeWords: [[CalcToken]] = [
        ["dp"], ["decimal"], ["decimals"], ["digits"], ["places"], ["decimal", "places"], ["decimal", "place"]
    ].map { $0.map { .ident($0) } }

    // MARK: - Fractions

    private static func fraction(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard
            let parts = tokens.operands(of: [nil, .ident("as"), .ident("fraction")])
                ?? tokens.operands(of: [nil, .ident("as"), .ident("a"), .ident("fraction")]),
            let value = CalcExpressionParser.value(parts[0]), case .scalar = value.kind,
            let (numerator, denominator) = simplestFraction(value.effective)
        else { return nil }
        let text = denominator == 1 ? "\(numerator)" : "\(numerator)/\(denominator)"
        return .phrase(query, .value(display: text, copyText: text), target: String(localized: "Fraction"))
    }

    /// The continued-fraction convergent within a billionth of `value`, kept to readable denominators.
    private static func simplestFraction(_ value: Double) -> (numerator: Int, denominator: Int)? {
        guard value.isFinite, abs(value) < 1e9 else { return nil }
        let target = abs(value)
        var (previousNumerator, numerator) = (0.0, 1.0)
        var (previousDenominator, denominator) = (1.0, 0.0)
        var remainder = target
        for _ in 0..<32 {
            let whole = remainder.rounded(.down)
            (previousNumerator, numerator) = (numerator, whole * numerator + previousNumerator)
            (previousDenominator, denominator) = (denominator, whole * denominator + previousDenominator)
            guard denominator <= 10_000 else { return nil }
            if abs(numerator / denominator - target) <= 1e-9 * max(1, target) {
                return (value < 0 ? -Int(numerator) : Int(numerator), Int(denominator))
            }
            remainder = 1 / (remainder - whole)
            guard remainder.isFinite else { return nil }
        }
        return nil
    }
}
