import Foundation

/// Questions about a date rather than arithmetic on it: `week number`, `day of year`, `age 1990-05-03`.
enum CalcDateFacts {
    private enum Fact {
        case week
        case dayOfYear
        case age
        case weekday
        case weekOfMonth
        case dayOfMonth

        /// Longest first, so `what week number is it` is not read as `what week`.
        static let phrases: [(String, Fact)] = [
            ("what day of the year is it", .dayOfYear), ("what day of year is it", .dayOfYear),
            ("what week number is it", .week), ("what week of the year is it", .week),
            ("what week is it", .week), ("current week number", .week), ("week of the year", .week),
            ("week of year", .week),
            ("week of the month", .weekOfMonth), ("week of month", .weekOfMonth),
            ("day of the month", .dayOfMonth), ("day of month", .dayOfMonth),
            ("day of the year", .dayOfYear), ("day of the week", .weekday), ("week number", .week),
            ("day of year", .dayOfYear), ("day number", .dayOfYear), ("weekday", .weekday),
            ("born on", .age), ("born", .age), ("age of", .age), ("age", .age)
        ]
    }

    static func evaluate(_ raw: String, now: Date, calendar: Calendar) -> CalcResult? {
        // Every phrase is two words or more and starts with one of these letters.
        guard raw.utf8.count <= 64, let first = raw.utf8.first, "wdabchmsWDABCHMS".utf8.contains(first),
            raw.utf8.contains(32)
        else { return nil }
        let query = raw.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if let count = periodCount(query, now: now, calendar: calendar) { return count }
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

        let day = format(date, "EEEE, d MMMM, yyyy", calendar: calendar)
        switch fact {
        case .week:
            return card(
                query, day, String(localized: "Week of the Year"), calendar.component(.weekOfYear, from: date)
            )
        case .dayOfYear:
            guard let ordinal = calendar.ordinality(of: .day, in: .year, for: date) else { return nil }
            return card(query, day, String(localized: "Day of the Year"), ordinal)
        case .weekOfMonth:
            return card(
                query, day, String(localized: "Week of the Month"),
                calendar.component(.weekOfMonth, from: date))
        case .dayOfMonth:
            return card(
                query, day, String(localized: "Day of the Month"), calendar.component(.day, from: date))
        case .age:
            return age(query, born: date, rest: rest, day: day, now: now, calendar: calendar)
        case .weekday:
            let name = format(date, "EEEE", calendar: calendar)
            return CalcResult(
                expression: query, sourceBadge: format(date, "d MMMM, yyyy", calendar: calendar),
                targetBadge: String(localized: "Day of the Week"),
                payload: .value(display: name, copyText: name), canChain: false)
        }
    }

    private static func format(_ date: Date, _ pattern: String, calendar: Calendar) -> String {
        CalcDateFormatters.string(from: date, calendar: calendar, zone: calendar.timeZone, pattern: pattern)
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

    // MARK: - Counts over a period

    private static func periodCount(_ query: String, now: Date, calendar: Calendar) -> CalcResult? {
        var words = query.split(separator: " ").map(String.init)
        guard words.count >= 3, let unit = PeriodUnit(words[0]) else { return nil }
        words.removeFirst()
        let remaining = words.first == "left" || words.first == "remaining"
        if remaining { words.removeFirst() }
        guard words.count >= 2, words.removeFirst() == "in",
            let period = period(words.joined(separator: " "), now: now, calendar: calendar)
        else { return nil }
        var start: Date? = period.interval.start
        if remaining, period.interval.start < now {
            guard now < period.interval.end else { return nil }
            start =
                unit.countsDays
                ? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) : now
        }
        guard let start, let value = unit.count(from: start, to: period.interval.end, calendar: calendar)
        else {
            return nil
        }
        return CalcResult(
            expression: query, sourceBadge: period.label,
            targetBadge: remaining ? String(localized: "Remaining") : String(localized: "Total"),
            payload: .number(value, suffix: " " + (value == 1 ? unit.singular : unit.plural)), canChain: false
        )
    }

    private enum PeriodUnit {
        case seconds, minutes, hours, days, weeks, workdays

        init?(_ word: String) {
            switch word {
            case "seconds", "second": self = .seconds
            case "minutes", "minute", "mins": self = .minutes
            case "hours", "hour", "hrs": self = .hours
            case "days", "day": self = .days
            case "weeks", "week": self = .weeks
            case "workdays", "workday", "weekdays", "businessdays": self = .workdays
            default: return nil
            }
        }

        /// Calendar units count whole days, so what remains of today is never part of them.
        var countsDays: Bool { self == .days || self == .weeks || self == .workdays }

        var singular: String {
            switch self {
            case .seconds: "second"
            case .minutes: "minute"
            case .hours: "hour"
            case .days: "day"
            case .weeks: "week"
            case .workdays: "workday"
            }
        }

        var plural: String { singular + "s" }

        func count(from start: Date, to end: Date, calendar: Calendar) -> Double? {
            guard start <= end else { return 0 }
            switch self {
            case .seconds: return end.timeIntervalSince(start)
            case .minutes: return end.timeIntervalSince(start) / 60
            case .hours: return end.timeIntervalSince(start) / 3600
            case .days, .weeks:
                guard let days = calendar.dateComponents([.day], from: start, to: end).day else { return nil }
                return self == .weeks ? Double(days) / 7 : Double(days)
            case .workdays:
                return CalcDateTime.businessDays(from: start, to: end, calendar: calendar).map(Double.init)
            }
        }
    }

    private static func period(
        _ phrase: String, now: Date, calendar: Calendar
    ) -> (interval: DateInterval, label: String)? {
        let component: Calendar.Component
        let date: Date
        switch phrase {
        case "the year", "this year", "year":
            (component, date) = (.year, now)
        case "the month", "this month", "month":
            (component, date) = (.month, now)
        case "today", "the day":
            (component, date) = (.day, now)
        default:
            if phrase.count == 4, let year = Int(phrase),
                let first = calendar.date(from: DateComponents(year: year, month: 1, day: 1))
            {
                (component, date) = (.year, first)
            } else if let first = CalcDateTime.day("1 " + phrase, now: now, calendar: calendar) {
                // The month's first day names it, so a bare `february` takes the nearest year.
                (component, date) = (.month, first)
            } else {
                return nil
            }
        }
        guard let interval = calendar.dateInterval(of: component, for: date) else { return nil }
        let pattern = component == .year ? "yyyy" : component == .month ? "MMMM yyyy" : "EEEE, d MMMM"
        return (interval, format(interval.start, pattern, calendar: calendar))
    }
}
