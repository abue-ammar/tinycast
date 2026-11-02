import Foundation

/// Questions about a date rather than arithmetic on it: `week number`, `day of year`, `age 1990-05-03`.
enum CalcDateFacts {
    private enum Fact {
        case week
        case dayOfYear
        case age

        /// Longest first, so `what week number is it` is not read as `what week`.
        static let phrases: [(String, Fact)] = [
            ("what day of the year is it", .dayOfYear), ("what day of year is it", .dayOfYear),
            ("what week number is it", .week), ("what week of the year is it", .week),
            ("what week is it", .week), ("current week number", .week), ("week of the year", .week),
            ("day of the year", .dayOfYear), ("week number", .week), ("day of year", .dayOfYear),
            ("day number", .dayOfYear), ("born on", .age), ("born", .age), ("age of", .age), ("age", .age)
        ]
    }

    static func evaluate(_ raw: String, now: Date, calendar: Calendar) -> CalcResult? {
        // Every phrase is two words or more and starts with one of these letters.
        guard raw.utf8.count <= 64, let first = raw.utf8.first, "wdabcWDABC".utf8.contains(first),
            raw.utf8.contains(32)
        else { return nil }
        let query = raw.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard let (phrase, fact) = Fact.phrases.first(where: { matches(query, $0.0) }) else { return nil }
        var rest = String(query.dropFirst(phrase.count)).trimmingCharacters(in: .whitespaces)
        if fact != .age {
            for lead in ["of ", "for ", "on "] where rest.hasPrefix(lead) { rest.removeFirst(lead.count) }
        }

        let date: Date
        if rest.isEmpty {
            guard fact != .age else { return nil }
            date = calendar.startOfDay(for: now)
        } else if let named = CalcDateTime.day(rest, now: now, calendar: calendar) {
            date = named
        } else {
            return nil
        }

        let day = CalcDateFormatters.string(
            from: date, calendar: calendar, zone: calendar.timeZone, pattern: "EEEE, d MMMM, yyyy")
        switch fact {
        case .week:
            return card(
                query, day, String(localized: "Week of the Year"), calendar.component(.weekOfYear, from: date)
            )
        case .dayOfYear:
            guard let ordinal = calendar.ordinality(of: .day, in: .year, for: date) else { return nil }
            return card(query, day, String(localized: "Day of the Year"), ordinal)
        case .age:
            return age(query, born: date, rest: rest, day: day, now: now, calendar: calendar)
        }
    }

    /// The phrase must end the query or be followed by a word, so `ages` and `agent` are not `age`.
    private static func matches(_ query: String, _ phrase: String) -> Bool {
        query == phrase || query.hasPrefix(phrase + " ")
    }

    private static func card(_ query: String, _ day: String, _ badge: String, _ value: Int) -> CalcResult {
        CalcResult(
            expression: query, sourceBadge: day, targetBadge: badge, payload: .number(Double(value)),
            canChain: false)
    }

    /// A year has to be written, because a bare `3 may` could be any birth year.
    private static func age(
        _ query: String, born: Date, rest: String, day: String, now: Date, calendar: Calendar
    ) -> CalcResult? {
        guard writesYear(rest), born <= now,
            let years = calendar.dateComponents([.year], from: born, to: now).year
        else { return nil }
        return CalcResult(
            expression: query, sourceBadge: day, targetBadge: String(localized: "Age"),
            payload: .number(Double(years), suffix: years == 1 ? " year" : " years"), canChain: false)
    }

    private static func writesYear(_ text: String) -> Bool {
        var run = 0
        for character in text {
            run = character.isASCII && character.isNumber ? run + 1 : 0
            if run == 4 { return true }
        }
        return false
    }
}
