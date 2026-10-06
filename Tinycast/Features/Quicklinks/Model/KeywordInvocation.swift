import Foundation

/// Splits an Alfred-style invocation: a keyword, a space, and the query it runs with.
enum KeywordInvocation {
    /// The text after `keyword` in `query`, or nil when the query isn't that keyword's call.
    static func remainder(query: String, keyword: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty, trimmed.count > keyword.count,
            trimmed.prefix(keyword.count).compare(keyword, options: .caseInsensitive)
                == .orderedSame
        else { return nil }
        let after = trimmed.index(trimmed.startIndex, offsetBy: keyword.count)
        guard trimmed[after].isWhitespace else { return nil }
        let rest = trimmed[trimmed.index(after: after)...].trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : String(rest)
    }
}
