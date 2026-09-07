import Foundation

enum CalcTokenizer {
    /// nil on any character that can't be calculator input — "not a calculation", not an error.
    static func tokenize(_ input: String) -> [CalcToken]? {
        let chars = Array(input.unicodeScalars)
        var tokens: [CalcToken] = []
        tokens.reserveCapacity(chars.count / 2 + 1)
        var i = 0
        var depth = 0
        var functionDepth: Int?

        func isDigit(_ ch: Unicode.Scalar) -> Bool { (48...57).contains(ch.value) }

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
                while end < chars.count, chars[end].isASCII && Character(chars[end]).isHexDigit { end += 1 }
                if end > start, let value = UInt64(String(String.UnicodeScalarView(chars[start..<end])), radix: radix) {
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
                        text.unicodeScalars.append(c)
                    } else if c == "," && functionDepth == nil && i + 1 < chars.count && isDigit(chars[i + 1]) {
                        // grouping separator between digits — skip
                    } else if c == "." && !seenDot {
                        seenDot = true
                        text.unicodeScalars.append(c)
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
                        text += String(String.UnicodeScalarView(chars[i..<end]))
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
                let start = i
                while i < chars.count, chars[i].isLetter { i += 1 }
                var text = String(String.UnicodeScalarView(chars[start..<i]))
                if i < chars.count, isDigit(chars[i]) {
                    let prefix = text.lowercased()
                    if CalcUnits.byName[prefix] == nil, CalcCurrency.byName[prefix] != nil {
                        tokens.append(.ident(prefix))
                        continue
                    }
                }
                while i < chars.count {
                    let c = chars[i]
                    if c.isLetter || c.isCombiningMark || c == "°" || isDigit(c) {
                        text.unicodeScalars.append(c)
                    } else if c == "²" {
                        text.append("2")
                    } else if c == "³" {
                        text.append("3")
                    } else {
                        break
                    }
                    i += 1
                }
                if let unit = compoundUnit(chars, after: i, prefix: text) {
                    tokens.append(.ident(unit.name))
                    i = unit.end
                } else {
                    tokens.append(.ident(CalcUnits.byName[text] != nil ? text : text.lowercased()))
                }
                continue
            }

            // Signs are punctuation, so fold to ISO: `€20 to gbp` tokenizes as `20 eur to gbp`.
            if let code = CurrencyData.signs[Character(ch)] {
                tokens.append(.ident(code))
                i += 1
                continue
            }

            // "**" is the Python/JS/shell spelling of power, same operator as "^".
            if ch == "*", i + 1 < chars.count, chars[i + 1] == "*" {
                tokens.append(.op(.power))
                i += 2
                continue
            }

            if i + 1 < chars.count {
                let combined: CalcOperator? = switch (ch, chars[i + 1]) {
                case ("<", "<"): .shiftLeft
                case (">", ">"): .shiftRight
                case ("=", "="): .equal
                case ("!", "="): .notEqual
                case ("<", "="): .lessEqual
                case (">", "="): .greaterEqual
                default: nil
                }
                if let op = combined {
                    tokens.append(.op(op))
                    i += 2
                    continue
                }
            }
            if ch == "(" {
                if functionDepth == nil, case .ident(let name)? = tokens.last, CalcMath.isFunction(name) {
                    functionDepth = depth
                }
                depth += 1
            } else if ch == ")" {
                depth -= 1
                if functionDepth == depth { functionDepth = nil }
            }
            switch ch {
            case "+", "(", ")", "!", "%", "^", "&", "|", "~", "<", ">", "≤", "≥", "≠", "⊻":
                guard let op = CalcOperator(rawValue: Character(ch)) else { return nil }
                tokens.append(.op(op))
            case ",":
                tokens.append(.comma)
            case "*", "×":
                tokens.append(.op(.multiply))
            case "/", "÷":
                tokens.append(.op(.divide))
            case "−":
                tokens.append(.op(.subtract))
            case "-":
                if i + 1 < chars.count, chars[i + 1] == ">" {
                    tokens.append(.arrow)
                    i += 1
                } else {
                    tokens.append(.op(.subtract))
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

    /// Only a spelling the table resolves, so `6/2(1+2)` keeps dividing.
    private static func compoundUnit(
        _ chars: [Unicode.Scalar], after index: Int, prefix: String
    ) -> (name: String, end: Int)? {
        guard index < chars.count, chars[index] == "/" || chars[index].isWhitespace else { return nil }
        let separator = chars[index] == "/" ? "/" : " "
        var rightStart = index + 1
        while rightStart < chars.count, chars[rightStart].isWhitespace { rightStart += 1 }
        var end = rightStart
        while end < chars.count, chars[end].isLetter || chars[end].isNumber { end += 1 }
        guard end > rightStart else { return nil }
        let spelling = (prefix + separator + String(String.UnicodeScalarView(chars[rightStart..<end])))
            .replacingOccurrences(of: "²", with: "2")
            .replacingOccurrences(of: "³", with: "3")
        let name = CalcUnits.byName[spelling] != nil ? spelling : spelling.lowercased()
        guard CalcUnits.byName[name] != nil else { return nil }
        return (name, end)
    }

    /// Whether the `k` at `index` is a thousands suffix rather than Kelvin or a unit's head.
    private static func isCompactSuffix(_ chars: [Unicode.Scalar], _ index: Int) -> Bool {
        let next = index + 1
        guard next < chars.count else { return true }
        if isTemperatureConversion(chars, from: next) { return false }
        guard chars[next].isLetter else { return true }

        var end = next
        while end < chars.count, chars[end].isLetter { end += 1 }
        return CalcCurrency.byName[String(String.UnicodeScalarView(chars[next..<end])).lowercased()] != nil
    }

    /// True when the rest reads as a conversion into a temperature unit, keeping `k` as Kelvin.
    private static func isTemperatureConversion(_ chars: [Unicode.Scalar], from index: Int) -> Bool {
        let remainder = String(String.UnicodeScalarView(chars[index...]))
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

private extension Unicode.Scalar {
    var isLetter: Bool {
        if isASCII { return (65...90).contains(value) || (97...122).contains(value) }
        return CharacterSet.letters.contains(self)
    }

    var isWhitespace: Bool { properties.isWhitespace }
    var isNumber: Bool { properties.numericType != nil }
    var isCombiningMark: Bool {
        properties.generalCategory == .nonspacingMark || properties.generalCategory == .spacingMark
    }
}
