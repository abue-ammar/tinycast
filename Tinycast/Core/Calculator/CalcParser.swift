import Foundation

enum CalcToken: Equatable, Sendable {
    case number(Double)
    /// Radix-prefixed integer literal (0xff / 0b1010 / 0o777), kept exact for base conversion.
    case intLiteral(UInt64, radix: Int)
    /// Lowercased word (function, constant, unit, or connector); `²`/`³` fold to "2"/"3" so `m²` and `m2` match, while `°` is kept.
    case ident(String)
    case op(Character)  // + - * / ^ ! % ( )
    case arrow  // -> or →
}

enum CalcTokenizer {
    /// nil on any character that can't be calculator input — the caller treats that as "not a calculation", never an error.
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

            // Radix literals: 0x… / 0b… / 0o… — needs ≥1 digit after the prefix, else fall through so "0" parses as a plain number.
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
                guard let value = Double(text) else { return nil }
                tokens.append(.number(value))
                continue
            }

            if ch.isLetter || ch == "°" {
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

            // Currency signs are punctuation, not letters: fold each to its ISO code so `€20 to gbp` tokenizes exactly like `20 eur to gbp`.
            if let code = CurrencyData.signs[ch] {
                tokens.append(.ident(code))
                i += 1
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
}

/// Precedence-climbing evaluator over the token stream (evaluates while parsing, no AST), returning nil for anything malformed or non-finite.
enum CalcParser {
    static func evaluate(_ tokens: [CalcToken]) -> Double? {
        var parser = Parser(tokens: tokens)
        guard let result = parser.parseExpression(minBP: 0), parser.isAtEnd,
            result.effective.isFinite
        else { return nil }
        return result.effective
    }

    // Capture-free closures (not bare C function references) so every entry infers `@Sendable` under both language modes — the harness compiles this in Swift 5.
    fileprivate static let functions: [String: @Sendable (Double) -> Double] = [
        "sqrt": { sqrt($0) }, "log": { log10($0) }, "ln": { log($0) }, "sin": { sin($0) },
        "cos": { cos($0) }, "tan": { tan($0) }, "abs": { abs($0) }, "floor": { floor($0) },
        "ceil": { ceil($0) }, "round": { $0.rounded() },
    ]

    fileprivate static let constants: [String: Double] = ["pi": .pi, "π": .pi, "e": M_E]
}

private struct Parser {
    /// A value that may still be a "percent" (`20%`): additive ops treat it as a relative change, everything else as value/100.
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

    // Binding powers: additive 10, multiplicative (incl. "of") 20, unary minus 25, power 30 (right-assoc), postfix ! % deg tightest.
    private static let unaryBP = 25

    mutating func parseExpression(minBP: Int) -> Value? {
        guard var lhs = parseOperand() else { return nil }
        while let (op, bp, rightBP) = peekBinary(), bp >= minBP {
            pos += 1
            guard let rhs = parseExpression(minBP: rightBP) else { return nil }
            guard let combined = apply(op, lhs, rhs) else { return nil }
            lhs = combined
        }
        return lhs
    }

    /// (operator, its binding power, minimum bp for its right operand).
    private func peekBinary() -> (Character, Int, Int)? {
        switch current {
        case .op(let op) where op == "+" || op == "-": return (op, 10, 11)
        case .op(let op) where op == "*" || op == "/": return (op, 20, 21)
        case .ident("of"): return ("*", 20, 21)
        case .op("^"): return ("^", 30, 30)  // right-associative: 2^3^2 = 512
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
                guard !value.isPercent, let fact = factorial(value.value) else { return nil }
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
                    // Bare application: `sqrt 64`, `sin 30deg` — the argument is one operand, so `sqrt 64 + 36` is sqrt(64) + 36.
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

    /// Factorial for non-negative integers; 170! is the last value representable as a Double.
    private func factorial(_ v: Double) -> Double? {
        guard v >= 0, v.rounded() == v, v <= 170 else { return nil }
        var result = 1.0
        var n = 2.0
        while n <= v {
            result *= n
            n += 1
        }
        return result
    }
}
