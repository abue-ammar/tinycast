import Foundation

/// Reductions over a spoken list: `average of 10, 20 and 30`, `median of 3 km, 1 km, 2 km`.
enum CalcStatistics {
    static func evaluate(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard tokens.count >= 3, case .ident(let lead) = tokens[0], leads.contains(lead) else { return nil }
        for statistic in statistics where tokens.starts(with: statistic.head) {
            let items = splitList(tokens.dropFirst(statistic.head.count))
            guard items.count >= 2 else { return nil }
            // Lowered to the function call, so a list keeps units exactly as `sum(…)` does.
            let call =
                [.ident(statistic.function), .op(.open)] + items.joined(separator: [.comma]) + [.op(.close)]
            guard let value = CalcExpressionParser.value(call) else { return nil }
            return .phrase(query, .quantity(value), target: statistic.badge, isCurrency: value.isCurrency)
        }
        return nil
    }

    /// The badge names which reduction ran, so `min` and `max` are told apart on the card.
    private struct Statistic {
        let head: [CalcToken]
        let function: String
        let badge: String
    }

    private static let statistics: [Statistic] = {
        let average = String(localized: "Average")
        let sum = String(localized: "Sum")
        let minimum = String(localized: "Minimum")
        let maximum = String(localized: "Maximum")
        let result = String(localized: "Result")
        let rows: [(String, String, String)] = [
            ("average of", "average", average), ("avg of", "average", average),
            ("mean of", "average", average),
            ("midpoint between", "average", average), ("midpoint of", "average", average),
            ("halfway between", "average", average),
            ("sum of", "sum", sum), ("total of", "sum", sum),
            ("min of", "min", minimum), ("smaller of", "min", minimum), ("lesser of", "min", minimum),
            ("max of", "max", maximum), ("larger of", "max", maximum), ("greater of", "max", maximum),
            ("median of", "median", String(localized: "Median")),
            ("count of", "count", String(localized: "Count")),
            ("standard deviation of", "stddev", String(localized: "Standard Deviation")),
            ("std dev of", "stddev", String(localized: "Standard Deviation")),
            ("stddev of", "stddev", String(localized: "Standard Deviation")),
            ("gcd of", "gcd", result), ("gcf of", "gcd", result),
            ("greatest common divisor of", "gcd", result), ("greatest common factor of", "gcd", result),
            ("lcm of", "lcm", result), ("lowest common multiple of", "lcm", result),
            ("least common multiple of", "lcm", result)
        ]
        return rows.map { phrase, function, badge in
            Statistic(
                head: phrase.split(separator: " ").map { .ident(String($0)) }, function: function,
                badge: badge)
        }
    }()

    private static let leads: Set<String> = Set(
        statistics.compactMap { statistic in
            guard case .ident(let name)? = statistic.head.first else { return nil }
            return name
        })

    /// Items split on top-level `,` or `and`, so `sum of 2*3, 4` stays two operands.
    private static func splitList(_ tokens: ArraySlice<CalcToken>) -> [[CalcToken]] {
        var items: [[CalcToken]] = []
        var current: [CalcToken] = []
        var depth = 0
        for token in tokens {
            if token == .op(.open) { depth += 1 }
            if token == .op(.close) { depth -= 1 }
            if depth == 0, token == .comma || token == .ident("and") {
                guard !current.isEmpty else { return [] }
                items.append(current)
                current = []
            } else {
                current.append(token)
            }
        }
        guard !current.isEmpty else { return [] }
        items.append(current)
        return items
    }
}
