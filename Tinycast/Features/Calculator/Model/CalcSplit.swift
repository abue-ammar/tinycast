import Foundation

/// A shared amount: `85 + 20% split 3`, `split $120 between 4`, `120 / 4 people`.
enum CalcSplit {
    private struct Phrase {
        let amount: String
        let count: Int
    }

    private static let joiners: Set<String> = ["between", "among", "by", "into", "in"]
    private static let headcounts: Set<String> = [
        "people", "persons", "person", "ways", "way", "guests", "friends", "diners"
    ]

    /// A scan of tokens already in hand, so a query with none of these words pays nothing more.
    static func mentions(_ tokens: [CalcToken]) -> Bool {
        tokens.contains { token in
            guard case .ident(let name) = token else { return false }
            return name == "split" || name == "between" || name == "among" || headcounts.contains(name)
        }
    }

    private static func parse(_ query: String) -> Phrase? {
        guard query.count <= 128 else { return nil }
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let lower = words.map { $0.lowercased() }
        guard words.count >= 3 else { return nil }

        if lower[0] == "split",
            let joiner = lower.indices.dropFirst(2).first(where: { joiners.contains(lower[$0]) })
        {
            return phrase(Array(words[1..<joiner]), Array(lower[(joiner + 1)...]))
        }
        if let marker = lower.indices.dropFirst().first(where: {
            ["split", "between", "among"].contains(lower[$0])
        }) {
            var tail = Array(lower[(marker + 1)...])
            if let first = tail.first, joiners.contains(first) { tail.removeFirst() }
            return phrase(Array(words[..<marker]), tail)
        }
        // `120 / 4 people`: the divide is already there, so only the trailing noun is dropped.
        if headcounts.contains(lower[lower.count - 1]), Int(lower[lower.count - 2]) != nil,
            ["/", "÷"].contains(lower[lower.count - 3])
        {
            return phrase(Array(words[..<(words.count - 3)]), [lower[lower.count - 2]])
        }
        return nil
    }

    private static func phrase(_ amount: [String], _ tail: [String]) -> Phrase? {
        var tail = tail
        if let last = tail.last, headcounts.contains(last) { tail.removeLast() }
        guard !amount.isEmpty, tail.count == 1, let count = Int(tail[0]), (1...10_000).contains(count)
        else { return nil }
        return Phrase(amount: amount.joined(separator: " "), count: count)
    }

    /// Divides before rounding and before any `to`, so `$1 / 6 split 2` matches `$1 / 6 / 2`.
    static func evaluate(_ query: String, rates: CurrencyRates?, region: String?) -> CalcResult? {
        guard let phrase = parse(query), let tokens = CalcTokenizer.tokenize(phrase.amount), !tokens.isEmpty
        else { return nil }
        let expression = query.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let count = Double(phrase.count)
        if let amount = CalcPercent.amount(tokens) {
            return CalcResult(
                expression: expression, sourceBadge: String(localized: "Expression"),
                targetBadge: String(localized: "Per Person"), payload: .number(amount / count))
        }
        let end = CalcQuantity.conversionTarget(tokens, from: 0, to: tokens.count)?.start ?? tokens.count
        let divided =
            [.op(.open)] + tokens[..<end] + [.op(.close), .op(.divide), .number(count)] + tokens[end...]
        guard
            let each = CalcQuantity.evaluate(
                divided, query: phrase.amount, rates: rates, region: region, preserveStandaloneUnit: true),
            case .value = each.payload, each.canChain
        else { return nil }
        return CalcResult(
            expression: expression, sourceBadge: each.sourceBadge,
            targetBadge: String(localized: "Per Person"), payload: each.payload, isCurrency: each.isCurrency)
    }
}
