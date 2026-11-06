import Foundation

/// An answer re-spelled in another notation: `1234567 to sci`, `51.4772° to dms`, `5400 s to hms`.
enum CalcNumberForm {
    static func evaluate(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard tokens.count >= 3, case .ident(let last) = tokens.last, keywords.contains(last) else {
            return nil
        }
        for (words, form) in forms {
            let start = tokens.count - words.count - 1
            guard start > 0, CalcUnits.isConnector(tokens[start]),
                tokens[(start + 1)...].elementsEqual(words.map { CalcToken.ident($0) }),
                let value = CalcExpressionParser.value(Array(tokens[..<start]))
            else { continue }
            return answer(value, form: form, query: query)
        }
        return nil
    }

    private enum Form {
        case scientific, degreesMinutesSeconds, hoursMinutesSeconds, lapTime, multiplier, plain
    }

    private static let forms: [([String], Form)] = [
        (["scientific", "notation"], .scientific), (["sci", "not"], .scientific),
        (["scientific"], .scientific),
        (["sci"], .scientific), (["dms"], .degreesMinutesSeconds), (["hms"], .hoursMinutesSeconds),
        (["laptime"], .lapTime), (["lap", "time"], .lapTime),
        (["multiplier"], .multiplier), (["multiple"], .multiplier), (["plain", "number"], .plain),
        (["number"], .plain), (["num"], .plain)
    ]

    private static let keywords: Set<String> = Set(forms.compactMap { $0.0.last })

    private static func answer(_ value: CalcValue, form: Form, query: String) -> CalcResult? {
        switch form {
        case .scientific:
            guard case .scalar = value.kind, let text = scientific(value.effective) else { return nil }
            return .phrase(
                query, .value(display: text, copyText: text), target: String(localized: "Scientific"))
        case .degreesMinutesSeconds:
            let degrees: Double
            switch value.kind {
            case .scalar: degrees = value.effective
            case .unit(let unit) where unit.category == .angle:
                guard let degree = CalcUnits.byName["deg"] else { return nil }
                degrees = value.amount * unit.factor / degree.factor
            default: return nil
            }
            let text = sexagesimal(degrees, marks: ("° ", "′ ", "″"))
            return .phrase(
                query, .value(display: text, copyText: text),
                target: String(localized: "Degrees, Minutes, Seconds"),
                canChain: false)
        case .hoursMinutesSeconds:
            guard case .unit(let unit) = value.kind, unit.category == .time, let hour = CalcUnits.byName["hr"]
            else { return nil }
            let text = sexagesimal(value.amount * unit.factor / hour.factor, marks: ("h ", "m ", "s"))
            return .phrase(
                query, .value(display: text, copyText: text),
                target: String(localized: "Hours, Minutes, Seconds"),
                canChain: false)
        case .lapTime:
            guard case .unit(let unit) = value.kind, unit.category == .time, value.amount >= 0 else {
                return nil
            }
            let text = lapTime(value.amount * unit.factor)
            return .phrase(
                query, .value(display: text, copyText: text), target: String(localized: "Lap Time"),
                canChain: false)
        case .multiplier:
            guard case .scalar = value.kind else { return nil }
            return CalcSpokenMath.multiplierCard(value.effective, query: query)
        case .plain:
            guard case .scalar = value.kind else { return nil }
            return .phrase(query, .number(value.effective), target: String(localized: "Result"))
        }
    }

    /// `1.234567e6`: up to ten significant digits, which the tokenizer reads back as the same number.
    private static func scientific(_ value: Double) -> String? {
        guard value.isFinite else { return nil }
        guard value != 0 else { return "0e0" }
        let exponent = Int(floor(log10(abs(value))))
        var mantissa = String(format: "%.9f", value / pow(10, Double(exponent)))
        while mantissa.hasSuffix("0") { mantissa.removeLast() }
        if mantissa.hasSuffix(".") { mantissa.removeLast() }
        // Rounding can carry the mantissa to ten: 9.9999999999 is 1e1, not 10e0.
        if mantissa == "10" || mantissa == "-10" { return "\(mantissa.dropLast())e\(exponent + 1)" }
        return "\(mantissa)e\(exponent)"
    }

    private static func lapTime(_ seconds: Double) -> String {
        let milliseconds = (seconds * 1000).rounded()
        let whole = Int(milliseconds / 1000)
        let fraction = milliseconds.truncatingRemainder(dividingBy: 1000)
        var text = String(format: "%02ld:%02ld:%02ld", whole / 3600, whole / 60 % 60, whole % 60)
        if fraction > 0 {
            var digits = String(format: "%03.0f", fraction)
            while digits.hasSuffix("0") { digits.removeLast() }
            text += "." + digits
        }
        return text
    }

    /// A whole unit, then sixtieths and their sixtieths, the last kept to two decimals.
    private static func sexagesimal(_ value: Double, marks: (String, String, String)) -> String {
        let sign = value < 0 ? "-" : ""
        let hundredths = (abs(value) * 360_000).rounded()
        let whole = (hundredths / 360_000).rounded(.down)
        let minutes = ((hundredths - whole * 360_000) / 6_000).rounded(.down)
        let seconds = (hundredths - whole * 360_000 - minutes * 6_000) / 100
        return "\(sign)\(CalcFormatter.display(whole))\(marks.0)\(Int(minutes))\(marks.1)"
            + "\(CalcFormatter.display(seconds))\(marks.2)"
    }
}
