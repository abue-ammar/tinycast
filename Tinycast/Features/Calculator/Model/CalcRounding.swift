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
        "round", "rounded", "nearest", "dp", "decimal", "decimals", "digit", "digits", "places", "fraction",
        "frac"
    ]

    // MARK: - Rounding

    private static func rounded(_ tokens: [CalcToken], query: String) -> CalcResult? {
        var rest = tokens[...]
        var rule: FloatingPointRoundingRule?
        let leadsWithRound = rest.first == .ident("round")
        if leadsWithRound {
            rest.removeFirst()
            rule = direction(&rest)
        }
        let stops: [CalcToken] =
            leadsWithRound
            ? [.ident("rounded"), .ident("to"), .ident("up"), .ident("down")]
            : [.ident("rounded"), .ident("to")]
        guard let end = rest.firstIndex(where: stops.contains),
            var value = CalcExpressionParser.value(Array(rest[..<end])), !value.isPercent
        else { return nil }
        rest = rest[end...]
        let named = rest.first == .ident("rounded")
        if named || (leadsWithRound && rest.first != .ident("to")) {
            guard rule == nil else { return nil }
            if named { rest.removeFirst() }
            rule = direction(&rest)
        }
        let precision: Precision
        if rest.isEmpty {
            guard rule != nil || named else { return nil }
            precision = .step(1)
        } else {
            guard rest.first == .ident("to"),
                let target = self.precision(Array(rest.dropFirst()), rule: &rule)
            else { return nil }
            precision = target
        }
        value.amount = precision.apply(to: value.amount, rule: rule ?? .toNearestOrAwayFromZero)
        guard value.amount.isFinite else { return nil }
        return .phrase(
            query, .quantity(value), target: String(localized: "Rounded"), isCurrency: value.isCurrency)
    }

    private static func direction(_ rest: inout ArraySlice<CalcToken>) -> FloatingPointRoundingRule? {
        switch rest.first {
        case .ident("up"):
            rest.removeFirst()
            return .up
        case .ident("down"):
            rest.removeFirst()
            return .down
        default:
            return nil
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

    /// `nearest 5`, `next 10`, `nearest 8th`, `2 dp`; a bare `10` is a step only after `up` or `down`.
    private static func precision(_ tokens: [CalcToken], rule: inout FloatingPointRoundingRule?) -> Precision?
    {
        var target = tokens[...]
        if target.first == .ident("the") { target.removeFirst() }
        switch target.first {
        case .ident("nearest"):
            target.removeFirst()
        case .ident("next"), .ident("last"):
            let implied: FloatingPointRoundingRule = target.first == .ident("next") ? .up : .down
            guard rule == nil || rule == implied else { return nil }
            rule = implied
            target.removeFirst()
        default:
            if rule != nil, let step = CalcExpressionParser.scalar(Array(target)), step > 0 {
                return .step(step)
            }
            guard let places = target.first.flatMap(CalcQuantity.numberValue), places.rounded() == places,
                (0...15).contains(places), placeWords.contains(Array(target.dropFirst()))
            else { return nil }
            return .decimals(Int(places))
        }
        if target.count == 1, case .ident(let name) = target.first, let step = stepWords[name] {
            return .step(step)
        }
        if target.count == 2, let denominator = target.first.flatMap(CalcQuantity.numberValue),
            case .ident(let suffix) = target.last, ["st", "nd", "rd", "th"].contains(suffix), denominator >= 2
        {
            return .step(1 / denominator)
        }
        guard let step = CalcExpressionParser.scalar(Array(target)), step > 0 else { return nil }
        return .step(step)
    }

    private static let stepWords: [String: Double] = [
        "ten": 10, "hundred": 100, "thousand": 1_000, "million": 1_000_000,
        "half": 0.5, "third": 1.0 / 3, "quarter": 0.25, "tenth": 0.1, "hundredth": 0.01, "thousandth": 0.001
    ]

    private static let placeWords: [[CalcToken]] = [
        ["dp"], ["digit"], ["digits"], ["decimal"], ["decimals"], ["places"], ["decimal", "places"],
        ["decimal", "place"], ["decimal", "point"], ["decimal", "points"]
    ].map { $0.map { .ident($0) } }

    // MARK: - Fractions

    private static func fraction(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard
            let parts = fractionTargets.lazy.compactMap({ tokens.operands(of: $0) }).first,
            let value = CalcExpressionParser.value(parts[0]), case .scalar = value.kind,
            let (numerator, denominator) = simplestFraction(value.effective)
        else { return nil }
        let text = denominator == 1 ? "\(numerator)" : "\(numerator)/\(denominator)"
        return .phrase(query, .value(display: text, copyText: text), target: String(localized: "Fraction"))
    }

    private static let fractionTargets: [[CalcToken?]] = ["as", "to", "in"].flatMap { connector in
        [["fraction"], ["a", "fraction"], ["frac"]].map { words in
            [nil, .ident(connector)] + words.map { .ident($0) }
        }
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
