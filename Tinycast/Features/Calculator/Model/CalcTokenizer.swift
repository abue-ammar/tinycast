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
            if ch == "0", i + 2 < chars.count, let base = literalBase(chars[i + 1]) {
                let start = i + 2
                var end = start
                while end < chars.count, chars[end].isASCII && Character(chars[end]).isHexDigit { end += 1 }
                if end > start,
                    let value = UInt64(
                        String(String.UnicodeScalarView(chars[start..<end])), radix: base.rawValue)
                {
                    tokens.append(.intLiteral(value, base: base))
                    i = end
                    continue
                }
            }

            if isDigit(ch), let fraction = unitFraction(chars, at: i) {
                tokens.append(.number(fraction.value))
                i = fraction.end
                continue
            }

            if isDigit(ch) || (ch == "." && i + 1 < chars.count && isDigit(chars[i + 1])) {
                var text = ""
                var seenDot = false
                while i < chars.count {
                    let c = chars[i]
                    if isDigit(c) {
                        text.unicodeScalars.append(c)
                    } else if c == "," && functionDepth == nil && i + 1 < chars.count && isDigit(chars[i + 1])
                    {
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
                    let scaled = value * 1_000
                    guard scaled.isFinite else { return nil }
                    tokens.append(.compactNumber(scaled))
                    i += 1
                } else if let magnitude = magnitudeWord(chars, after: i)
                    ?? currencyMagnitude(chars, after: i, previous: tokens.last)
                {
                    let scaled = value * magnitude.scale
                    guard scaled.isFinite else { return nil }
                    tokens.append(.compactNumber(scaled))
                    i = magnitude.end
                } else if isShorthand {
                    tokens.append(.compactNumber(value))
                } else {
                    tokens.append(.number(value))
                }
                continue
            }

            if ch == "x" || ch == "X", isMultiplicationX(chars, at: i, previous: tokens.last) {
                tokens.append(.op(.multiply))
                i += 1
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
                if let previous = tokens.last, endsOperand(previous), mayBeWordOperator(text),
                    let word = wordOperator(text.lowercased(), chars, after: i)
                {
                    tokens.append(contentsOf: word.tokens)
                    i = word.end
                    continue
                }
                if let head = spokenRootHead(text.lowercased()),
                    followingWords(["root"], chars, after: i) != nil
                {
                    tokens.append(.ident(head))
                    continue
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

            if let mark = lengthMark(ch), i > 0, isDigit(chars[i - 1]) {
                tokens.append(.ident(mark))
                i += 1
                continue
            }

            if ch == "*", i + 1 < chars.count, chars[i + 1] == "*" {
                tokens.append(.op(.power))
                i += 2
                continue
            }

            if i + 1 < chars.count {
                let combined: CalcOperator? =
                    switch (ch, chars[i + 1]) {
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

    private static func literalBase(_ prefix: Unicode.Scalar) -> CalcNumberBase? {
        switch prefix {
        case "x", "X": .hexadecimal
        case "b", "B": .binary
        case "o", "O": .octal
        default: nil
        }
    }

    private static func isMultiplicationX(
        _ chars: [Unicode.Scalar], at index: Int, previous: CalcToken?
    ) -> Bool {
        guard index > 0, !chars[index - 1].isLetter, let previous, endsOperand(previous) else {
            return false
        }
        var end = index + 1
        while end < chars.count, chars[end].isLetter { end += 1 }
        if end > index + 1 {
            let name = String(String.UnicodeScalarView(chars[index..<end])).lowercased()
            if name == "xor" || CalcCurrency.byName[name] != nil { return false }
        }
        let attached = !chars[index - 1].isWhitespace
        var next = index + 1
        while next < chars.count, chars[next].isWhitespace { next += 1 }
        guard next < chars.count else { return !attached }
        switch chars[next] {
        case ")", "!", "%", "^", "/", ",", "=", "*", "×", "÷", "−", "→":
            return false
        default:
            return true
        }
    }

    /// Every spoken operator is two to ten letters and starts with one of these.
    private static func mayBeWordOperator(_ text: String) -> Bool {
        guard (2...10).contains(text.utf8.count), let first = text.utf8.first else { return false }
        return "pmtdscrePMTDSCRE".utf8.contains(first)
    }

    private static func spokenRootHead(_ word: String) -> String? {
        switch word {
        case "squared": "square"
        case "cubed": "cube"
        default: nil
        }
    }

    private static func wordOperator(
        _ word: String, _ chars: [Unicode.Scalar], after index: Int
    ) -> (tokens: [CalcToken], end: Int)? {
        let attached = index < chars.count && (chars[index].isNumber || chars[index].isCombiningMark)
        guard !attached else { return nil }
        switch word {
        case "per":
            if let end = followingWords(["cent"], chars, after: index) { return ([.op(.percent)], end) }
            return ([.op(.divide)], index)
        case "percent", "percentage": return ([.op(.percent)], index)
        case "exponent": return ([.op(.power)], index)
        case "raised":
            guard let end = followingWords(["to"], chars, after: index) else { return nil }
            return ([.op(.power)], followingWords(["the", "power", "of"], chars, after: end) ?? end)
        case "plus": return ([.op(.add)], index)
        case "minus": return ([.op(.subtract)], index)
        case "times": return ([.op(.multiply)], index)
        case "squared": return ([.op(.power), .number(2)], index)
        case "cubed": return ([.op(.power), .number(3)], index)
        case "divided", "multiplied":
            guard let end = followingWords(["by"], chars, after: index) else { return nil }
            return ([.op(word == "divided" ? .divide : .multiply)], end)
        case "to":
            if let end = followingWords(["the", "power", "of"], chars, after: index) {
                return ([.op(.power)], end)
            }
            // `3 to the 9`: only a digit after `the`, so `to the nearest 10` keeps rounding.
            guard let end = followingWords(["the"], chars, after: index), end < chars.count,
                chars[end].isWhitespace,
                chars[(end + 1)...].first(where: { !$0.isWhitespace })?.isNumber == true
            else { return nil }
            return ([.op(.power)], end)
        default: return nil
        }
    }

    private static func followingWords(
        _ expected: [String], _ chars: [Unicode.Scalar], after index: Int
    ) -> Int? {
        var end = index
        for word in expected {
            var start = end
            while start < chars.count, chars[start].isWhitespace { start += 1 }
            end = start
            while end < chars.count, chars[end].isLetter { end += 1 }
            guard String(String.UnicodeScalarView(chars[start..<end])).lowercased() == word else {
                return nil
            }
        }
        return end
    }

    /// Only before a unit, so spaced `1 / 20ms` and a bare `5/2 - 1/2` keep dividing.
    private static func unitFraction(_ chars: [Unicode.Scalar], at start: Int) -> (value: Double, end: Int)? {
        guard let first = integer(chars, from: start) else { return nil }
        var whole = 0.0
        var numerator = first
        if first.end < chars.count, chars[first.end].isWhitespace {
            var next = first.end
            while next < chars.count, chars[next].isWhitespace { next += 1 }
            guard let part = integer(chars, from: next) else { return nil }
            whole = first.value
            numerator = part
        }
        guard numerator.end < chars.count, chars[numerator.end] == "/",
            let denominator = integer(chars, from: numerator.end + 1), denominator.value != 0,
            namesUnit(chars, from: denominator.end)
        else { return nil }
        return (whole + numerator.value / denominator.value, denominator.end)
    }

    private static func integer(_ chars: [Unicode.Scalar], from start: Int) -> (value: Double, end: Int)? {
        var end = start
        while end < chars.count, (48...57).contains(chars[end].value) { end += 1 }
        guard end > start, end - start <= 15, end == chars.count || chars[end] != "." else { return nil }
        return Double(String(String.UnicodeScalarView(chars[start..<end]))).map { ($0, end) }
    }

    private static func namesUnit(_ chars: [Unicode.Scalar], from index: Int) -> Bool {
        if index < chars.count, lengthMark(chars[index]) != nil { return true }
        var start = index
        while start < chars.count, chars[start].isWhitespace { start += 1 }
        var end = start
        while end < chars.count, chars[end].isLetter || (end > start && chars[end].isNumber) { end += 1 }
        guard end > start else { return false }
        let name = String(String.UnicodeScalarView(chars[start..<end]))
        return CalcUnits.byName[name] != nil || CalcUnits.byName[name.lowercased()] != nil
            || compoundUnit(chars, after: end, prefix: name) != nil
    }

    private static func lengthMark(_ ch: Unicode.Scalar) -> String? {
        switch ch {
        case "\"", "″", "”": "inch"
        case "'", "′", "’": "ft"
        default: nil
        }
    }

    /// `$5M`, `€2bn`: only right after a currency, where `m` and `b` can't mean metre or byte.
    private static func currencyMagnitude(
        _ chars: [Unicode.Scalar], after index: Int, previous: CalcToken?
    ) -> (scale: Double, end: Int)? {
        guard case .ident(let code)? = previous, CalcCurrency.byName[code] != nil else { return nil }
        var end = index
        while end < chars.count, chars[end].isLetter { end += 1 }
        guard end > index, end == chars.count || !chars[end].isNumber else { return nil }
        switch String(String.UnicodeScalarView(chars[index..<end])) {
        case "m", "M": return (1e6, end)
        case "b", "B", "bn": return (1e9, end)
        case "t", "T", "tn": return (1e12, end)
        default: return nil
        }
    }

    private static func endsOperand(_ token: CalcToken) -> Bool {
        switch token {
        case .number, .compactNumber, .intLiteral:
            true
        case .op(let op):
            op == .close || op == .factorial || op == .percent
        case .ident(let name):
            !["to", "in", "of", "mod", "power", "and"].contains(name)
        case .arrow, .comma:
            false
        }
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

    /// Short scale only: the engine reads canonical English, where a billion is 10⁹.
    private static let magnitudes: [String: Double] = [
        "thousand": 1e3, "million": 1e6, "billion": 1e9, "trillion": 1e12, "quadrillion": 1e15
    ]

    /// The scale of a whole magnitude word following a literal (`13 million`), and where it ends.
    private static func magnitudeWord(
        _ chars: [Unicode.Scalar], after index: Int
    ) -> (scale: Double, end: Int)? {
        var start = index
        while start < chars.count, chars[start].isWhitespace { start += 1 }
        var end = start
        while end < chars.count, chars[end].isLetter { end += 1 }
        guard end > start else { return nil }
        if end < chars.count, chars[end].isNumber || chars[end].isCombiningMark { return nil }
        guard let scale = magnitudes[String(String.UnicodeScalarView(chars[start..<end])).lowercased()]
        else { return nil }
        return (scale, end)
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
