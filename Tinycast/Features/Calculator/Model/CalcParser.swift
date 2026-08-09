import Foundation

enum CalcToken: Equatable, Sendable {
    case number(Double)
    /// Shorthand (`10k`, `1e5`), kept distinct so a lone one still earns a card.
    case compactNumber(Double)
    /// Radix-prefixed integer literal (0xff / 0b1010 / 0o777), kept exact for base conversion.
    case intLiteral(UInt64, radix: Int)
    /// Lowercased word; `²`/`³` fold to "2"/"3" so `m²` matches `m2`, while `°` is kept.
    case ident(String)
    case op(Character)  // + - * / ^ ! % ( )
    case arrow  // -> or →
}

enum CalcTokenizer {
    /// nil on any character that can't be calculator input — "not a calculation", not an error.
    static func tokenize(_ input: String) -> [CalcToken]? {
        let chars = Array(input)
        var tokens: [CalcToken] = []
        var i = 0

        func isDigit(_ ch: Character) -> Bool { ch.isASCII && ch.isNumber }

        while i < chars.count {
            let ch = chars[i]
            if ch.isWhitespace {
                i += 1
                continue
            }

            // Radix literals need ≥1 digit after the prefix, else "0" is a plain number.
            if ch == "0", i + 2 < chars.count,
                let radix = ["x": 16, "b": 2, "o": 8][String(chars[i + 1]).lowercased()]
            {
                let start = i + 2
                var end = start
                while end < chars.count, chars[end].isHexDigit { end += 1 }
                if end > start, let value = UInt64(String(chars[start..<end]), radix: radix) {
                    tokens.append(.intLiteral(value, radix: radix))
                    i = end
                    continue
                }
            }

            if isDigit(ch) || (ch == "." && i + 1 < chars.count && isDigit(chars[i + 1])) {
                var text = ""
                var seenDot = false
                while i < chars.count {
                    let c = chars[i]
                    if isDigit(c) {
                        text.append(c)
                    } else if c == "," && i + 1 < chars.count && isDigit(chars[i + 1]) {
                        // grouping separator between digits — skip
                    } else if c == "." && !seenDot {
                        seenDot = true
                        text.append(c)
                    } else {
                        break
                    }
                    i += 1
                }
                // Only while the exponent hugs the mantissa — a spaced `2 e` stays 2 × e.
                var isShorthand = false
                if i < chars.count, chars[i] == "e" || chars[i] == "E" {
                    var digits = i + 1
                    if digits < chars.count, chars[digits] == "+" || chars[digits] == "-" {
                        digits += 1
                    }
                    var end = digits
                    while end < chars.count, isDigit(chars[end]) { end += 1 }
                    if end > digits {
                        text += String(chars[i..<end])
                        i = end
                        isShorthand = true
                    }
                }
                // An overflowing literal ("1e400") isn't calculator input, so no card.
                guard let value = Double(text), value.isFinite else { return nil }
                // Attached `k` is ×1,000; whitespace keeps Kelvin, and `10kg` stays a unit.
                if i < chars.count, chars[i] == "k" || chars[i] == "K", isCompactSuffix(chars, i) {
                    tokens.append(.compactNumber(value * 1_000))
                    i += 1
                } else if isShorthand {
                    tokens.append(.compactNumber(value))
                } else {
                    tokens.append(.number(value))
                }
                continue
            }

            if ch.isLetter || ch == "°" {
                // Split an attached currency prefix (`USD1K`) before the ident scanner eats it.
                if ch.isLetter {
                    var letterEnd = i
                    while letterEnd < chars.count, chars[letterEnd].isLetter { letterEnd += 1 }
                    if letterEnd < chars.count, isDigit(chars[letterEnd]) {
                        let prefix = String(chars[i..<letterEnd]).lowercased()
                        if CalcUnits.byName[prefix] == nil, CalcCurrency.byName[prefix] != nil {
                            tokens.append(.ident(prefix))
                            i = letterEnd
                            continue
                        }
                    }
                }
                var text = ""
                while i < chars.count {
                    let c = chars[i]
                    if c.isLetter || c == "°" || isDigit(c) {
                        text.append(c)
                    } else if c == "²" {
                        text.append("2")
                    } else if c == "³" {
                        text.append("3")
                    } else {
                        break
                    }
                    i += 1
                }
                tokens.append(.ident(text.lowercased()))
                continue
            }

            // Signs are punctuation, so fold to ISO: `€20 to gbp` tokenizes as `20 eur to gbp`.
            if let code = CurrencyData.signs[ch] {
                tokens.append(.ident(code))
                i += 1
                continue
            }

            // "**" is the Python/JS/shell spelling of power, same operator as "^".
            if ch == "*", i + 1 < chars.count, chars[i + 1] == "*" {
                tokens.append(.op("^"))
                i += 2
                continue
            }

            switch ch {
            case "+", "(", ")", "!", "%", "^":
                tokens.append(.op(ch))
            case "*", "×":
                tokens.append(.op("*"))
            case "/", "÷":
                tokens.append(.op("/"))
            case "−":
                tokens.append(.op("-"))
            case "-":
                if i + 1 < chars.count, chars[i + 1] == ">" {
                    tokens.append(.arrow)
                    i += 1
                } else {
                    tokens.append(.op("-"))
                }
            case "→":
                tokens.append(.arrow)
            case "=":
                // Tolerate a trailing "=" ("2+2="); anywhere else it's not calculator input.
                guard i == chars.count - 1 else { return nil }
            default:
                return nil
            }
            i += 1
        }
        return tokens
    }

    /// Whether the `k` at `index` is a thousands suffix rather than Kelvin or a unit's head.
    private static func isCompactSuffix(_ chars: [Character], _ index: Int) -> Bool {
        let next = index + 1
        guard next < chars.count else { return true }
        if isTemperatureConversion(chars, from: next) { return false }
        guard chars[next].isLetter else { return true }

        var end = next
        while end < chars.count, chars[end].isLetter { end += 1 }
        return CalcCurrency.byName[String(chars[next..<end]).lowercased()] != nil
    }

    /// True when the rest reads as a conversion into a temperature unit, keeping `k` as Kelvin.
    private static func isTemperatureConversion(_ chars: [Character], from index: Int) -> Bool {
        let remainder = String(chars[index...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        for connector in ["to", "in", "->", "→"] where remainder.hasPrefix(connector) {
            let target = remainder.dropFirst(connector.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if CalcUnits.byName[target]?.category == .temperature { return true }
        }
        return false
    }
}

/// Precedence-climbing evaluator, no AST; nil for anything malformed or non-finite.
enum CalcParser {
    static func evaluate(_ tokens: [CalcToken]) -> Double? {
        var parser = Parser(tokens: tokens)
        guard let result = parser.parseExpression(minBP: 0), parser.isAtEnd,
            result.effective.isFinite
        else { return nil }
        return result.effective
    }

    // Capture-free closures, not C function refs, so every entry infers `@Sendable` in Swift 5.
    fileprivate static let functions: [String: @Sendable (Double) -> Double] = [
        "sqrt": { sqrt($0) }, "log": { log10($0) }, "ln": { log($0) }, "sin": { sin($0) },
        "cos": { cos($0) }, "tan": { tan($0) }, "abs": { abs($0) }, "floor": { floor($0) },
        "ceil": { ceil($0) }, "round": { $0.rounded() }
    ]

    fileprivate static let constants: [String: Double] = ["pi": .pi, "π": .pi, "e": M_E]

    /// Factorial for non-negative integers; 170! is the last value representable as a Double.
    static func factorial(_ value: Double) -> Double? {
        guard value >= 0, value.rounded() == value, value <= 170 else { return nil }
        var result = 1.0
        var next = 2.0
        while next <= value {
            result *= next
            next += 1
        }
        return result
    }
}

private struct Parser {
    /// A value that may still be a "percent": relative for additive ops, else value/100.
    struct Value {
        var value: Double
        var isPercent = false
        var effective: Double { isPercent ? value / 100 : value }
    }

    let tokens: [CalcToken]
    var pos = 0

    init(tokens: [CalcToken]) { self.tokens = tokens }

    var isAtEnd: Bool { pos == tokens.count }
    private var current: CalcToken? { pos < tokens.count ? tokens[pos] : nil }

    // Binding powers: additive 10, multiplicative 20, unary 25, power 30, postfix tightest.
    private static let unaryBP = 25
    private static let mulBP = 20

    mutating func parseExpression(minBP: Int) -> Value? {
        guard var lhs = parseOperand() else { return nil }
        while true {
            if let binary = peekBinary(), binary.bindingPower >= minBP {
                pos += 1
                guard let rhs = parseExpression(minBP: binary.rightBindingPower) else { return nil }
                guard let combined = apply(binary.op, lhs, rhs) else { return nil }
                lhs = combined
                continue
            }
            // Juxtaposition is the operator here, so there's no token to consume before the rhs.
            if impliesMultiplication(), Self.mulBP >= minBP {
                guard let rhs = parseExpression(minBP: Self.mulBP + 1) else { return nil }
                guard let combined = apply("*", lhs, rhs) else { return nil }
                lhs = combined
                continue
            }
            break
        }
        return lhs
    }

    /// Deliberately narrow: no unit or currency ident is a constant, so `10km` keeps its path.
    private func impliesMultiplication() -> Bool {
        switch current {
        case .op("("): return true
        case .ident(let name): return CalcParser.constants[name] != nil || CalcParser.functions[name] != nil
        default: return false
        }
    }

    /// An operator, its binding power, and the minimum bp for its right operand.
    struct BinaryOp {
        let op: Character
        let bindingPower: Int
        let rightBindingPower: Int
    }

    private func peekBinary() -> BinaryOp? {
        switch current {
        case .op(let op) where op == "+" || op == "-":
            return BinaryOp(op: op, bindingPower: 10, rightBindingPower: 11)
        case .op(let op) where op == "*" || op == "/":
            return BinaryOp(op: op, bindingPower: Self.mulBP, rightBindingPower: Self.mulBP + 1)
        case .ident("of"):
            return BinaryOp(op: "*", bindingPower: Self.mulBP, rightBindingPower: Self.mulBP + 1)
        // Spelled-out only: "%" is already percent, and "20% - 5" gives no local signal.
        case .ident("mod"):
            return BinaryOp(op: "%", bindingPower: Self.mulBP, rightBindingPower: Self.mulBP + 1)
        case .op("^"):
            return BinaryOp(op: "^", bindingPower: 30, rightBindingPower: 30)  // right-associative: 2^3^2 = 512
        default: return nil
        }
    }

    private func apply(_ op: Character, _ lhs: Value, _ rhs: Value) -> Value? {
        let result: Double
        switch op {
        // `450 + 20%` reads as a relative change: 450 * 1.2. With a plain rhs it's ordinary math.
        case "+":
            result =
                rhs.isPercent
                ? lhs.effective * (1 + rhs.value / 100) : lhs.effective + rhs.effective
        case "-":
            result =
                rhs.isPercent
                ? lhs.effective * (1 - rhs.value / 100) : lhs.effective - rhs.effective
        case "*": result = lhs.effective * rhs.effective
        case "/": result = lhs.effective / rhs.effective
        case "%": result = lhs.effective.truncatingRemainder(dividingBy: rhs.effective)
        case "^": result = pow(lhs.effective, rhs.effective)
        default: return nil
        }
        return Value(value: result)
    }

    /// One prefix item plus all its postfixes (`!`, `%`, `deg`) — postfixes bind tightest.
    private mutating func parseOperand() -> Value? {
        guard var value = parsePrefix() else { return nil }
        loop: while true {
            switch current {
            case .op("!"):
                guard !value.isPercent, let fact = CalcParser.factorial(value.value) else {
                    return nil
                }
                value = Value(value: fact)
            case .op("%"):
                guard !value.isPercent else { return nil }
                value.isPercent = true
            case .ident("deg"):
                guard !value.isPercent else { return nil }
                value = Value(value: value.value * .pi / 180)
            default:
                break loop
            }
            pos += 1
        }
        return value
    }

    private mutating func parsePrefix() -> Value? {
        switch current {
        case .number(let n):
            pos += 1
            return Value(value: n)
        case .compactNumber(let n):
            pos += 1
            return Value(value: n)
        case .intLiteral(let n, _):
            pos += 1
            return Value(value: Double(n))
        case .op("-"):
            pos += 1
            guard let operand = parseExpression(minBP: Self.unaryBP) else { return nil }
            return Value(value: -operand.effective)
        case .op("+"):
            pos += 1
            return parseExpression(minBP: Self.unaryBP)
        case .op("("):
            pos += 1
            guard let inner = parseExpression(minBP: 0), case .op(")") = current else { return nil }
            pos += 1
            return inner
        case .ident(let name):
            if let constant = CalcParser.constants[name] {
                pos += 1
                return Value(value: constant)
            }
            if let fn = CalcParser.functions[name] {
                pos += 1
                let argument: Value?
                if case .op("(") = current {
                    pos += 1
                    argument = parseExpression(minBP: 0)
                    guard case .op(")") = current else { return nil }
                    pos += 1
                } else {
                    // Bare application takes one operand, so `sqrt 64 + 36` is sqrt(64) + 36.
                    argument = parseOperand()
                }
                guard let argument else { return nil }
                return Value(value: fn(argument.effective))
            }
            return nil
        default:
            return nil
        }
    }
}
