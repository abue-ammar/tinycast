import Foundation

/// Questions asked in words, reduced to the expression they ask about: `how many feet in a mile`.
enum CalcQuestion {
    /// What follows a leading `what is` or `calculate`, for the engine to try before the whole query.
    static func asked(_ query: String) -> String? {
        // Every lead starts with one of these, so ordinary queries skip lowercasing entirely.
        guard let first = query.utf8.first, "wWhHcCeE".utf8.contains(first), query.utf8.count > 8 else {
            return nil
        }
        let lowered = query.lowercased()
        for lead in leads where lowered.hasPrefix(lead) {
            let rest = query.dropFirst(lead.count).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? nil : rest
        }
        return nil
    }

    private static let leads = [
        "what is ", "what's ", "whats ", "how much is ", "calculate ", "compute ", "evaluate "
    ]

    /// The `amount to unit` conversion a worded one asks for, or nil when the tokens ask nothing.
    static func conversion(_ tokens: [CalcToken]) -> [CalcToken]? {
        guard tokens.count >= 3, case .ident(let lead) = tokens[0] else {
            return askedWhat(tokens)
        }
        switch lead {
        case "convert":
            let rest = tokens.dropFirst().map { $0 == .ident("into") ? .ident("to") : $0 }
            return rest.contains(where: CalcUnits.isConnector) || CalcCurrency.isPair(rest) ? rest : nil
        case "how":
            return howMany(tokens)
        case "exchange", "rate":
            return exchangeRate(tokens)
        default:
            return unitIn(tokens) ?? askedWhat(tokens)
        }
    }

    private static func askedWhat(_ tokens: [CalcToken]) -> [CalcToken]? {
        guard tokens.contains(.ident("is")) else { return nil }
        if let parts = tokens.operands(of: [nil, .ident("is"), .ident("what"), .ident("in"), nil])
            ?? tokens.operands(of: [nil, .ident("is"), .ident("what"), .ident("as"), nil])
            ?? tokens.operands(of: [nil, .ident("is"), .ident("how"), .ident("many"), nil])
            ?? tokens.operands(of: [nil, .ident("is"), .ident("how"), .ident("much"), .ident("in"), nil])
        {
            return parts[0] + [.ident("to")] + parts[1]
        }
        return nil
    }

    private static func howMany(_ tokens: [CalcToken]) -> [CalcToken]? {
        guard tokens[1] == .ident("many") || tokens[1] == .ident("much") else { return nil }
        let rest = Array(tokens.dropFirst(2)).filter { $0 != .ident("are") && $0 != .ident("is") }
        return unitIn(rest.map { $0 == .ident("per") || $0 == .op(.divide) ? .ident("in") : $0 })
    }

    /// `feet in a mile`, `cm in 5 inches`: the amount comes after the unit asked about.
    private static func unitIn(_ tokens: [CalcToken]) -> [CalcToken]? {
        guard tokens.count >= 3, case .ident(let target) = tokens[0], tokens[1] == .ident("in"),
            CalcUnits.byName[target] != nil || CalcCurrency.byName[target] != nil
        else { return nil }
        var source = Array(tokens.dropFirst(2))
        switch source[0] {
        case .ident("a"), .ident("an"), .ident("one"):
            source[0] = .number(1)
        case .number, .compactNumber, .op(.open):
            break
        default:
            return nil
        }
        guard source.count >= 2 else { return nil }
        return source + [.ident("to"), tokens[0]]
    }

    private static func exchangeRate(_ tokens: [CalcToken]) -> [CalcToken]? {
        var rest = tokens[...]
        if rest.first == .ident("exchange") { rest.removeFirst() }
        guard rest.first == .ident("rate") else { return nil }
        rest.removeFirst()
        if let lead = rest.first, [.ident("for"), .ident("from"), .ident("of")].contains(lead) {
            rest.removeFirst()
        }
        guard rest.count == 3, case .ident(let from) = rest.first, case .ident(let to) = rest.last,
            CalcUnits.isConnector(rest[rest.startIndex + 1]),
            CalcCurrency.byName[from] != nil, CalcCurrency.byName[to] != nil
        else { return nil }
        return [.number(1)] + rest
    }
}
