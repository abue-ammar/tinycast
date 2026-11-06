import Foundation

/// Compound growth and loan payments, such as `$1,000 after 3 years at 7%`.
enum CalcFinance {
    static func evaluate(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard tokens.contains(.ident("at")), tokens.contains(.op(.percent)) else { return nil }
        var rest = tokens[...]
        let ask = question(&rest)
        let periodsPerYear = compounding(&rest)
        guard let terms = terms(Array(rest)) else { return nil }

        var answer = terms.principal
        let badge: String
        switch ask {
        case .futureValue, .interest:
            let growth = pow(1 + terms.rate / periodsPerYear, periodsPerYear * terms.years)
            answer.amount *= ask == .interest ? growth - 1 : growth
            badge = ask == .interest ? String(localized: "Interest") : String(localized: "Future Value")
        case .payment(let frequency):
            let months = terms.years * 12
            guard months > 0 else { return nil }
            let monthlyRate = terms.rate / 12
            let monthly =
                monthlyRate == 0 ? 1 / months : monthlyRate / (1 - pow(1 + monthlyRate, -months))
            answer.amount *= monthly * frequency.months(over: months)
            badge = frequency.badge
        }
        guard answer.amount.isFinite else { return nil }
        return .phrase(query, .quantity(answer), target: badge, isCurrency: answer.isCurrency)
    }

    private enum Question: Equatable {
        case futureValue
        case interest
        case payment(Frequency)
    }

    private enum Frequency: Equatable {
        case monthly, annual, total

        func months(over term: Double) -> Double {
            switch self {
            case .monthly: 1
            case .annual: 12
            case .total: term
            }
        }

        var badge: String {
            switch self {
            case .monthly: String(localized: "Monthly Payment")
            case .annual: String(localized: "Annual Payment")
            case .total: String(localized: "Total Payment")
            }
        }
    }

    private static func question(_ rest: inout ArraySlice<CalcToken>) -> Question {
        if rest.starts(with: [.ident("interest"), .ident("on")]) {
            rest.removeFirst(2)
            return .interest
        }
        let frequencies: [String: Frequency] = [
            "monthly": .monthly, "annual": .annual, "yearly": .annual, "total": .total
        ]
        guard rest.count > 3, case .ident(let lead) = rest.first, let frequency = frequencies[lead],
            case .ident(let noun) = rest.dropFirst().first,
            ["payment", "payments", "repayment", "repayments"].contains(noun),
            rest.dropFirst(2).first == .ident("on")
        else { return .futureValue }
        rest.removeFirst(3)
        return .payment(frequency)
    }

    /// A trailing `compounding monthly` sets how often interest is added; yearly otherwise.
    private static func compounding(_ rest: inout ArraySlice<CalcToken>) -> Double {
        let periods: [String: Double] = [
            "daily": 365, "weekly": 52, "monthly": 12, "quarterly": 4, "yearly": 1, "annually": 1
        ]
        guard rest.count > 2, case .ident(let name)? = rest.last, let count = periods[name],
            rest.dropLast().last == .ident("compounding") || rest.dropLast().last == .ident("compounded")
        else { return 1 }
        rest.removeLast(2)
        return count
    }

    private struct Terms {
        let principal: CalcValue
        let years: Double
        let rate: Double
    }

    private static let termFirst: [CalcToken?] = [nil, .ident("for"), nil, .ident("at"), nil, .op(.percent)]
    private static let rateFirst: [CalcToken?] = [nil, .ident("at"), nil, .op(.percent), .ident("for"), nil]

    /// Term and yearly rate come in either order: `for 3 years at 7%` or `at 7% for 3 years`.
    private static func terms(_ tokens: [CalcToken]) -> Terms? {
        let normalized = tokens.map { $0 == .ident("after") || $0 == .ident("over") ? .ident("for") : $0 }
        let principal: [CalcToken]
        let term: [CalcToken]
        let rate: [CalcToken]
        if let parts = normalized.operands(of: termFirst) {
            (principal, term, rate) = (parts[0], parts[1], parts[2])
        } else if let parts = normalized.operands(of: rateFirst) {
            (principal, rate, term) = (parts[0], parts[1], parts[2])
        } else {
            return nil
        }
        guard let amount = CalcExpressionParser.value(principal), !amount.isPercent,
            let duration = CalcExpressionParser.value(term), case .unit(let unit) = duration.kind,
            unit.category == .time, let year = CalcUnits.byName["yr"],
            let percent = CalcExpressionParser.scalar(rate)
        else { return nil }
        let years = duration.amount * unit.factor / year.factor
        guard years > 0, years <= 1_000 else { return nil }
        return Terms(principal: amount, years: years, rate: percent / 100)
    }
}
