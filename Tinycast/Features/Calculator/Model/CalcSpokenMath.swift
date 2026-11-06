import Foundation

/// Math asked in words: `is 97 prime`, `5 choose 3`, `6 is to 600 as 8 is to what`.
enum CalcSpokenMath {
    static func evaluate(_ tokens: [CalcToken], query: String) -> CalcResult? {
        let mentions = tokens.contains { token in
            guard case .ident(let name) = token else { return false }
            return keywords.contains(name)
        }
        guard mentions else { return nil }
        return remainder(tokens, query: query) ?? prime(tokens, query: query) ?? clamp(tokens, query: query)
            ?? root(tokens, query: query)
            ?? proportion(tokens, query: query) ?? combinatorics(tokens, query: query)
            ?? logarithm(tokens, query: query) ?? multiplier(tokens, query: query)
    }

    private static let keywords: Set<String> = [
        "remainder", "prime", "clamp", "root", "to", "choose", "combination", "combinations", "permutation",
        "permutations", "logarithm", "log", "what", "multiplier"
    ]

    private typealias Pattern = [CalcToken?]

    private static func word(_ text: String) -> CalcToken { .ident(text) }

    private static func firstMatch(_ tokens: [CalcToken], _ patterns: [Pattern]) -> [[CalcToken]]? {
        for pattern in patterns {
            if let parts = tokens.operands(of: pattern) { return parts }
        }
        return nil
    }

    /// `(a) op (b)` through the typed parser, so units survive or cancel exactly as typed.
    private static func combined(_ a: [CalcToken], _ op: CalcOperator, _ b: [CalcToken]) -> [CalcToken] {
        [.op(.open)] + a + [.op(.close), .op(op), .op(.open)] + b + [.op(.close)]
    }

    // MARK: - Remainder

    private static func remainder(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard
            let parts = tokens.operands(of: [word("remainder"), word("of"), nil, .op(.divide), nil]),
            let dividend = CalcExpressionParser.scalar(parts[0]),
            let divisor = CalcExpressionParser.scalar(parts[1]), divisor != 0
        else { return nil }
        let result = dividend.truncatingRemainder(dividingBy: divisor)
        return result.isFinite ? .phrase(query, .number(result), target: String(localized: "Remainder")) : nil
    }

    // MARK: - Primality

    private static let primePatterns: [Pattern] = [
        [word("is"), nil, word("a"), word("prime"), word("number")],
        [word("is"), nil, word("a"), word("prime")],
        [word("is"), nil, word("prime")],
        [word("is"), word("prime"), nil]
    ]

    private static func prime(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard let parts = firstMatch(tokens, primePatterns),
            let value = CalcExpressionParser.scalar(parts[0]), value >= 0, value.rounded() == value,
            value <= 9_007_199_254_740_992
        else { return nil }
        let text = isPrime(UInt64(value)) ? "true" : "false"
        return .phrase(
            query, .value(display: text, copyText: text), target: String(localized: "Prime Number"),
            canChain: false)
    }

    /// Miller–Rabin with the bases that are deterministic for every 64-bit integer.
    private static func isPrime(_ n: UInt64) -> Bool {
        let bases: [UInt64] = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37]
        guard n >= 2 else { return false }
        for base in bases where n % base == 0 { return n == base }
        var odd = n - 1
        var twos = 0
        while odd % 2 == 0 {
            odd /= 2
            twos += 1
        }
        witnesses: for base in bases {
            var x = power(base, odd, modulo: n)
            if x == 1 || x == n - 1 { continue }
            for _ in 1..<twos {
                x = multiply(x, x, modulo: n)
                if x == n - 1 { continue witnesses }
            }
            return false
        }
        return true
    }

    private static func multiply(_ a: UInt64, _ b: UInt64, modulo m: UInt64) -> UInt64 {
        m.dividingFullWidth(a.multipliedFullWidth(by: b)).remainder
    }

    private static func power(_ base: UInt64, _ exponent: UInt64, modulo m: UInt64) -> UInt64 {
        var result: UInt64 = 1
        var base = base % m
        var exponent = exponent
        while exponent > 0 {
            if exponent & 1 == 1 { result = multiply(result, base, modulo: m) }
            base = multiply(base, base, modulo: m)
            exponent >>= 1
        }
        return result
    }

    // MARK: - Clamp

    private static func clamp(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard tokens.first == word("clamp") else { return nil }
        let parts: [[CalcToken]]
        if let matched = firstMatch(
            tokens,
            [
                [word("clamp"), nil, word("between"), nil, word("and"), nil],
                [word("clamp"), nil, word("from"), nil, word("to"), nil]
            ])
        {
            parts = matched
        } else if tokens.count == 4, tokens.dropFirst().allSatisfy({ CalcQuantity.numberValue($0) != nil }) {
            parts = tokens.dropFirst().map { [$0] }
        } else {
            return nil
        }
        guard let span = CalcExpressionParser.value(combined(parts[2], .subtract, parts[1])),
            span.amount >= 0,
            let clamped = CalcExpressionParser.value(
                [.ident("max"), .op(.open)] + parts[1] + [.comma, .ident("min"), .op(.open)] + parts[0]
                    + [.comma] + parts[2] + [.op(.close), .op(.close)])
        else { return nil }
        return .phrase(
            query, .quantity(clamped), target: String(localized: "Clamped"), isCurrency: clamped.isCurrency)
    }

    // MARK: - Roots

    /// `5 root of 100` is the fifth root; the parser already reads the `root 5 of 100` order.
    private static func root(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard let parts = tokens.operands(of: [nil, word("root"), word("of"), nil]),
            let degree = CalcExpressionParser.scalar(parts[0]), degree >= 2, degree.rounded() == degree,
            let value = CalcExpressionParser.scalar(parts[1]),
            let result = CalcMath.evaluate("root", [value, degree])
        else { return nil }
        return .phrase(query, .number(result), target: String(localized: "Root"))
    }

    // MARK: - Proportions

    /// `a : b = x : d` solved for the missing term, typed so `6 km is to 600 km as what is to 8 kg`.
    private static func proportion(_ tokens: [CalcToken], query: String) -> CalcResult? {
        let missingThird: [Pattern] = [
            [nil, word("is"), word("to"), nil, word("as"), word("what"), word("is"), word("to"), nil],
            [nil, word("to"), nil, word("as"), word("what"), word("to"), nil],
            [nil, word("to"), nil, word("is"), word("what"), word("to"), nil]
        ]
        let missingFourth: [Pattern] = [
            [nil, word("is"), word("to"), nil, word("as"), nil, word("is"), word("to"), word("what")],
            [nil, word("to"), nil, word("as"), nil, word("to"), word("what")],
            [nil, word("to"), nil, word("is"), nil, word("to"), word("what")]
        ]
        let product: [CalcToken]
        if let parts = firstMatch(tokens, missingThird) {
            product = combined(combined(parts[0], .multiply, parts[2]), .divide, parts[1])
        } else if let parts = firstMatch(tokens, missingFourth) {
            product = combined(combined(parts[1], .multiply, parts[2]), .divide, parts[0])
        } else {
            return nil
        }
        guard let value = CalcExpressionParser.value(product), value.amount.isFinite else { return nil }
        return .phrase(
            query, .quantity(value), target: String(localized: "Proportion"), isCurrency: value.isCurrency)
    }

    // MARK: - Combinations and permutations

    /// A phrase shape, whether it counts combinations, and whether it names `k` before `n`.
    private static let arrangementPatterns: [(pattern: Pattern, combination: Bool, countFirst: Bool)] = [
        ([nil, word("combinations"), word("of"), nil], true, true),
        ([nil, word("combination"), word("of"), nil], true, true),
        ([nil, word("permutations"), word("of"), nil], false, true),
        ([nil, word("permutation"), word("of"), nil], false, true),
        ([nil, word("choose"), nil], true, false),
        ([nil, word("combination"), nil], true, false),
        ([nil, word("permutation"), nil], false, false)
    ]

    private static func combinatorics(_ tokens: [CalcToken], query: String) -> CalcResult? {
        for shape in arrangementPatterns {
            guard let parts = tokens.operands(of: shape.pattern) else { continue }
            let (nTokens, kTokens) = shape.countFirst ? (parts[1], parts[0]) : (parts[0], parts[1])
            guard let n = CalcExpressionParser.scalar(nTokens), let k = CalcExpressionParser.scalar(kTokens),
                let count = arrangements(n, k, combination: shape.combination)
            else { return nil }
            let badge =
                shape.combination ? String(localized: "Combinations") : String(localized: "Permutations")
            return .phrase(query, .number(count), target: badge)
        }
        return nil
    }

    /// `nCk` or `nPk` by running product, so neither ever forms a factorial larger than its answer.
    private static func arrangements(_ n: Double, _ k: Double, combination: Bool) -> Double? {
        guard n.rounded() == n, k.rounded() == k, k >= 0, n >= k, n <= 1e15 else { return nil }
        let steps = combination ? min(k, n - k) : k
        var result = 1.0
        var step = 0.0
        while step < steps {
            result *= n - step
            if combination { result /= step + 1 }
            guard result.isFinite else { return nil }
            step += 1
        }
        return combination ? result.rounded() : result
    }

    // MARK: - Logarithms

    private static func logarithm(_ tokens: [CalcToken], query: String) -> CalcResult? {
        let valueFirst: [Pattern] = [
            [word("logarithm"), nil, word("base"), nil],
            [word("logarithm"), word("of"), nil, word("to"), word("base"), nil],
            [word("logarithm"), word("of"), nil, word("with"), word("base"), nil],
            [nil, word("is"), nil, .op(.power), word("what")],
            [nil, word("is"), nil, word("to"), word("what"), word("power")]
        ]
        let baseFirst: [Pattern] = [
            [word("logarithm"), word("base"), nil, word("of"), nil],
            [word("log"), word("base"), nil, word("of"), nil],
            [word("logarithm"), nil, word("of"), nil],
            [nil, word("to"), word("what"), word("power"), word("is"), nil],
            [nil, word("to"), word("what"), .op(.power), word("is"), nil],
            [nil, word("with"), word("what"), word("power"), word("is"), nil],
            [nil, word("with"), word("what"), .op(.power), word("is"), nil]
        ]
        let candidates =
            valueFirst.compactMap { tokens.operands(of: $0) }.map { (value: $0[0], base: $0[1]) }
            + baseFirst.compactMap { tokens.operands(of: $0) }.map { (value: $0[1], base: $0[0]) }
        guard
            let result = candidates.lazy.compactMap({ operands -> Double? in
                guard let value = CalcExpressionParser.scalar(operands.value),
                    let base = CalcExpressionParser.scalar(operands.base)
                else { return nil }
                return CalcMath.evaluate("log", [value, base])
            }).first
        else { return nil }
        return .phrase(query, .number(result), target: String(localized: "Logarithm"))
    }

    // MARK: - Multipliers

    private static func multiplier(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard tokens.contains(word("multiplier")) else { return nil }
        let leads: [[CalcToken]] = [
            [word("as"), word("multiplier")], [word("as"), word("a"), word("multiplier")],
            [word("is"), word("what"), word("multiplier")]
        ]
        let relations: [(CalcToken, (Double) -> Double)] = [
            (word("of"), { $0 }), (word("on"), { $0 - 1 }), (word("off"), { 1 - $0 })
        ]
        for lead in leads {
            for (relation, adjust) in relations {
                guard let parts = tokens.operands(of: [nil] + lead + [relation, nil]),
                    let ratio = CalcExpressionParser.scalar(combined(parts[0], .divide, parts[1]))
                else { continue }
                return multiplierCard(adjust(ratio), query: query)
            }
            guard let parts = tokens.operands(of: [nil, word("to"), nil] + lead),
                let ratio = CalcExpressionParser.scalar(combined(parts[1], .divide, parts[0]))
            else { continue }
            return multiplierCard(ratio, query: query)
        }
        return nil
    }

    static func multiplierCard(_ value: Double, query: String) -> CalcResult? {
        guard value.isFinite else { return nil }
        return .phrase(
            query, .number(value, suffix: "x"), target: String(localized: "Multiplier"), canChain: false)
    }
}
