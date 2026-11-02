import Foundation

/// A shared amount: `85 + 20% split 3`, `split $120 between 4`, `120 / 4 people`.
enum CalcSplit {
    struct Phrase {
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

    /// The amount's own text and the headcount, or nil for anything that only resembles a split.
    static func parse(_ query: String) -> Phrase? {
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

    /// Each share of an answer that is a number, with its unit or currency carried over.
    static func share(of whole: CalcResult, among count: Int, query: String) -> CalcResult? {
        guard case .value(_, let copy) = whole.payload, whole.canChain else { return nil }
        let number = copy.prefix { !$0.isWhitespace }
        guard let amount = Double(number) else { return nil }
        let suffix = String(copy.dropFirst(number.count))
        let each = amount / Double(count)
        guard each.isFinite else { return nil }

        let payload: CalcResult.Payload
        if whole.isCurrency {
            let text = CalcFormatter.currency(each)
            payload = .value(display: CalcFormatter.grouped(text) + suffix, copyText: text + suffix)
        } else {
            payload = .number(each, suffix: suffix)
        }
        return CalcResult(
            expression: query.split(whereSeparator: \.isWhitespace).joined(separator: " "),
            sourceBadge: whole.sourceBadge, targetBadge: String(localized: "Per Person"), payload: payload,
            isCurrency: whole.isCurrency)
    }
}
