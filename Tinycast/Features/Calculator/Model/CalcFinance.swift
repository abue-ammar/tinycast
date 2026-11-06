import Foundation

/// Compound growth, loans and returns, such as `$1,000 after 3 years at 7%`.
enum CalcFinance {
    static func evaluate(_ tokens: [CalcToken], query: String) -> CalcResult? {
        if let investment = investmentReturn(tokens, query: query) { return investment }
        guard tokens.contains(.ident("at")), tokens.contains(.op(.percent)) else { return nil }
        return investmentRequired(tokens, query: query) ?? termsAnswer(tokens, query: query)
    }

    private static func termsAnswer(_ tokens: [CalcToken], query: String) -> CalcResult? {
        var rest = tokens[...]
        let ask = question(&rest)
        let periodsPerYear = compounding(&rest)
        guard let terms = terms(Array(rest)) else { return nil }

        var answer = terms.principal
        let badge: String
        switch ask {
        case .futureValue, .interest, .presentValue:
            let growth = pow(1 + terms.rate / periodsPerYear, periodsPerYear * terms.years)
            switch ask {
            case .interest:
                answer.amount *= growth - 1
                badge = String(localized: "Interest")
            case .presentValue:
                answer.amount /= growth
                badge = String(localized: "Present Value")
            default:
                answer.amount *= growth
                badge = String(localized: "Future Value")
            }
        case .payment(let frequency), .loanInterest(let frequency):
            let months = terms.years * 12
            guard months > 0 else { return nil }
            let monthlyRate = terms.rate / 12
            let monthly =
                monthlyRate == 0 ? 1 / months : monthlyRate / (1 - pow(1 + monthlyRate, -months))
            if case .loanInterest = ask {
                // Interest is what the payments add over the principal, spread like the payments are.
                answer.amount *= (monthly * months - 1) * frequency.months(over: months) / months
                badge = frequency.interestBadge
            } else {
                answer.amount *= monthly * frequency.months(over: months)
                badge = frequency.badge
            }
        }
        guard answer.amount.isFinite else { return nil }
        return .phrase(query, .quantity(answer), target: badge, isCurrency: answer.isCurrency)
    }

    private enum Question: Equatable {
        case futureValue
        case interest
        case presentValue
        case payment(Frequency)
        case loanInterest(Frequency)
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

        var interestBadge: String {
            switch self {
            case .monthly: String(localized: "Monthly Interest")
            case .annual: String(localized: "Annual Interest")
            case .total: String(localized: "Total Interest")
            }
        }
    }

    private static func question(_ rest: inout ArraySlice<CalcToken>) -> Question {
        for (lead, question) in [
            (["interest", "on"], Question.interest), (["present", "value", "of"], .presentValue),
            (["interest", "repayment", "on"], .loanInterest(.total))
        ] where rest.starts(with: lead.map { CalcToken.ident($0) }) {
            rest.removeFirst(lead.count)
            return question
        }
        let frequencies: [String: Frequency] = [
            "monthly": .monthly, "annual": .annual, "yearly": .annual, "total": .total
        ]
        guard rest.count > 3, case .ident(let lead) = rest.first, let frequency = frequencies[lead],
            case .ident(let noun) = rest.dropFirst().first
        else { return .futureValue }
        if ["payment", "payments", "repayment", "repayments"].contains(noun),
            rest.dropFirst(2).first == .ident("on")
        {
            rest.removeFirst(3)
            return .payment(frequency)
        }
        guard noun == "interest" else { return .futureValue }
        let tail = rest.dropFirst(2).first == .ident("repayment") ? 1 : 0
        guard rest.dropFirst(2 + tail).first == .ident("on") else { return .futureValue }
        rest.removeFirst(3 + tail)
        return .loanInterest(frequency)
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
            let years = years(term), years > 0, years <= 1_000,
            let percent = CalcExpressionParser.scalar(rate)
        else { return nil }
        return Terms(principal: amount, years: years, rate: percent / 100)
    }

    // MARK: - Returns

    private static func investmentReturn(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard tokens.contains(.ident("invested")) || tokens.contains(.ident("grew")) else { return nil }
        var rest = Array(tokens)
        for suffix: [CalcToken] in [[.ident("as"), .ident("a"), .op(.percent)], [.ident("as"), .op(.percent)]]
        where rest.count > suffix.count && Array(rest.suffix(suffix.count)) == suffix {
            rest.removeLast(suffix.count)
        }
        if let parts = rest.operands(of: [nil, .ident("invested"), nil, .ident("returned")]),
            let gain = ratio(parts[1], parts[0])
        {
            return percentCard((gain - 1) * 100, query: query, badge: String(localized: "Return"))
        }
        let perYear: [String: Double] = [
            "annual": 1, "annualized": 1, "yearly": 1, "quarterly": 4, "monthly": 12, "weekly": 52,
            "daily": 365
        ]
        guard rest.count > 3, case .ident(let lead) = rest[0], let periods = perYear[lead],
            rest[1] == .ident("return"), rest[2] == .ident("on")
        else { return nil }
        let normalized = Array(rest.dropFirst(3)).map {
            $0 == .ident("over") ? CalcToken.ident("after") : $0
        }
        guard
            let parts = normalized.operands(
                of: [nil, .ident("invested"), nil, .ident("returned"), .ident("after"), nil])
                ?? normalized.operands(of: [
                    nil, .ident("that"), .ident("grew"), .ident("to"), nil, .ident("after"), nil
                ]),
            let gain = ratio(parts[1], parts[0]), gain > 0,
            let years = years(parts[2]), years > 0
        else { return nil }
        let rate = pow(gain, 1 / (years * periods)) - 1
        return percentCard(rate * 100, query: query, badge: String(localized: "Return"))
    }

    /// `investment required for $50,000/year at 4%`: the capital whose yield pays that rate forever.
    private static func investmentRequired(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard
            let parts = tokens.operands(
                of: [
                    .ident("investment"), .ident("required"), .ident("for"), nil, .ident("at"), nil,
                    .op(.percent)
                ]),
            let rate = CalcExpressionParser.scalar(parts[1]), rate > 0,
            var yearly = CalcExpressionParser.value(
                [.op(.open)] + parts[0] + [.op(.close), .op(.multiply), .op(.open), .ident("yr"), .op(.close)]
            ),
            !yearly.isPercent
        else { return nil }
        yearly.amount /= rate / 100
        guard yearly.amount.isFinite else { return nil }
        return .phrase(
            query, .quantity(yearly), target: String(localized: "Investment"), isCurrency: yearly.isCurrency)
    }

    private static func ratio(_ a: [CalcToken], _ b: [CalcToken]) -> Double? {
        CalcExpressionParser.scalar(
            [.op(.open)] + a + [.op(.close), .op(.divide), .op(.open)] + b + [.op(.close)])
    }

    private static func years(_ tokens: [CalcToken]) -> Double? {
        guard let duration = CalcExpressionParser.value(tokens), case .unit(let unit) = duration.kind,
            unit.category == .time, let year = CalcUnits.byName["yr"]
        else { return nil }
        return duration.amount * unit.factor / year.factor
    }

    private static func percentCard(_ value: Double, query: String, badge: String) -> CalcResult? {
        value.isFinite ? .phrase(query, .number(value, suffix: "%"), target: badge) : nil
    }
}
