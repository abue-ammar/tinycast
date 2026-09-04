import Foundation

/// The presets and typed expressions Raycast's date picker offers ("tomorrow at 10am").
/// Pure: every environment fact — the calendar, the clock — arrives as a parameter.
enum ExtensionDateExpression {
    /// One row of the picker: a name, the date it means, and how that date reads.
    struct Suggestion: Equatable, Identifiable {
        let title: String
        /// nil clears the field, which is what "No Date" means.
        let date: Date?
        /// The right-hand column: the resolved day, or nothing for the clearing row.
        let detail: String?

        var id: String { title }
    }

    /// What the picker opens with, before anything is typed.
    static func presets(now: Date, calendar: Calendar, includesTime: Bool) -> [Suggestion] {
        var rows: [Suggestion] = [Suggestion(title: "No Date", date: nil, detail: nil)]
        let today = calendar.startOfDay(for: now)
        let offsets: [(String, Int)] = [("Today", 0), ("Tomorrow", 1), ("Yesterday", -1)]
        for (title, days) in offsets {
            guard let date = calendar.date(byAdding: .day, value: days, to: today) else { continue }
            rows.append(
                Suggestion(title: title, date: date, detail: detail(for: date, calendar: calendar)))
        }
        // The next four weekdays, so a whole week is reachable without typing a date.
        for offset in 2...5 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let name = weekdayName(date, calendar: calendar)
            rows.append(
                Suggestion(title: name, date: date, detail: detail(for: date, calendar: calendar)))
        }
        _ = includesTime
        return rows
    }

    /// Rows for what has been typed: the parse of it first, then the presets it matches.
    static func suggestions(
        query: String, now: Date, calendar: Calendar, includesTime: Bool
    ) -> [Suggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let presets = presets(now: now, calendar: calendar, includesTime: includesTime)
        guard !trimmed.isEmpty else { return presets }

        var rows: [Suggestion] = []
        if let parsed = parse(trimmed, now: now, calendar: calendar) {
            rows.append(
                Suggestion(
                    title: trimmed, date: parsed,
                    detail: detail(for: parsed, calendar: calendar, includesTime: includesTime)))
        }
        // A preset the typed text names is still worth offering, and never twice.
        for preset in presets where preset.title.localizedCaseInsensitiveContains(trimmed) {
            guard !rows.contains(where: { $0.date == preset.date }) else { continue }
            rows.append(preset)
        }
        return rows
    }

    /// "tomorrow", "next friday", "in 3 days", "5 sep", each optionally "at 10am".
    static func parse(_ expression: String, now: Date, calendar: Calendar) -> Date? {
        let lowered = expression.lowercased().trimmingCharacters(in: .whitespaces)
        guard !lowered.isEmpty else { return nil }

        // The time rides on whatever day the rest of the phrase resolves to.
        let (dayPhrase, time) = splitTime(lowered, calendar: calendar)
        guard let day = parseDay(dayPhrase, now: now, calendar: calendar) else { return nil }
        guard let time else { return day }
        return calendar.date(
            bySettingHour: time.hour, minute: time.minute, second: 0, of: day)
    }

    // MARK: - Days

    private static func parseDay(_ phrase: String, now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        let words = phrase.split(separator: " ").map(String.init)
        // An empty day phrase means "today at <time>", which is what a bare time reads as.
        guard !words.isEmpty else { return today }

        switch words.joined(separator: " ") {
        case "today", "now": return today
        case "tomorrow", "tmr": return calendar.date(byAdding: .day, value: 1, to: today)
        case "yesterday": return calendar.date(byAdding: .day, value: -1, to: today)
        default: break
        }

        // "in 3 days" / "in 2 weeks" / "in 1 month"
        if words.first == "in", words.count >= 3, let amount = Int(words[1]) {
            return calendar.date(byAdding: unit(words[2]), value: amount, to: today)
        }
        // "3 days" reads the same way without the preposition.
        if words.count >= 2, let amount = Int(words[0]) {
            if let unit = knownUnit(words[1]) {
                return calendar.date(byAdding: unit, value: amount, to: today)
            }
            // "5 sep" — a day number and a month name.
            if let month = monthNumber(words[1]) {
                return date(day: amount, month: month, onOrAfter: today, calendar: calendar)
            }
        }
        // "sep 5", the same date the other way round.
        if words.count >= 2, let month = monthNumber(words[0]), let amount = Int(words[1]) {
            return date(day: amount, month: month, onOrAfter: today, calendar: calendar)
        }
        // "next friday" / "friday" — the coming one either way; "next" only skips a same-day match.
        let wantsNext = words.first == "next"
        let name = wantsNext ? words.dropFirst().joined(separator: " ") : words.joined(separator: " ")
        if let weekday = weekdayNumber(name, calendar: calendar) {
            return nextDate(weekday: weekday, after: today, calendar: calendar)
        }
        return nil
    }

    /// Always forward: a weekday names the coming one, never the one just gone.
    private static func nextDate(weekday: Int, after today: Date, calendar: Calendar) -> Date? {
        for offset in 1...7 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: today) else {
                continue
            }
            if calendar.component(.weekday, from: candidate) == weekday { return candidate }
        }
        return nil
    }

    /// A bare day and month means the next one of those, so "5 jan" in December is next year.
    private static func date(
        day: Int, month: Int, onOrAfter today: Date, calendar: Calendar
    ) -> Date? {
        var components = calendar.dateComponents([.year], from: today)
        components.month = month
        components.day = day
        guard let candidate = calendar.date(from: components) else { return nil }
        if candidate >= today { return candidate }
        return calendar.date(byAdding: .year, value: 1, to: candidate)
    }

    private static func unit(_ word: String) -> Calendar.Component {
        knownUnit(word) ?? .day
    }

    private static func knownUnit(_ word: String) -> Calendar.Component? {
        switch word {
        case "day", "days": return .day
        case "week", "weeks": return .weekOfYear
        case "month", "months": return .month
        case "year", "years": return .year
        default: return nil
        }
    }

    // MARK: - Times

    private struct Time {
        let hour: Int
        let minute: Int
    }

    /// Splits "<day phrase> at <time>" and also catches a trailing bare "10am".
    private static func splitTime(_ phrase: String, calendar: Calendar) -> (String, Time?) {
        if let range = phrase.range(of: " at ") {
            let day = String(phrase[phrase.startIndex..<range.lowerBound])
            let rest = String(phrase[range.upperBound...])
            return (day, parseTime(rest))
        }
        // A phrase ending in a time, with no "at" — "tomorrow 10am".
        let words = phrase.split(separator: " ").map(String.init)
        if let last = words.last, let time = parseTime(last), words.count > 1 {
            return (words.dropLast().joined(separator: " "), time)
        }
        if let only = words.first, words.count == 1, let time = parseTime(only) {
            return ("", time)
        }
        return (phrase, nil)
    }

    /// "10am", "10:30", "22:15", "7 pm".
    private static func parseTime(_ text: String) -> Time? {
        let cleaned = text.replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty else { return nil }
        var body = cleaned
        var meridiem: String?
        for suffix in ["am", "pm"] where body.hasSuffix(suffix) {
            meridiem = suffix
            body = String(body.dropLast(2))
        }
        let parts = body.split(separator: ":", maxSplits: 1).map(String.init)
        guard let first = parts.first, var hour = Int(first) else { return nil }
        let minute = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            if meridiem == "pm", hour < 12 { hour += 12 }
            if meridiem == "am", hour == 12 { hour = 0 }
        } else if parts.count == 1 {
            // A bare number is a time only when written as one: "10:00", never "10".
            return nil
        }
        return Time(hour: hour, minute: minute)
    }

    // MARK: - Naming

    private static func weekdayName(_ date: Date, calendar: Calendar) -> String {
        let index = calendar.component(.weekday, from: date) - 1
        return calendar.weekdaySymbols[index]
    }

    private static func weekdayNumber(_ name: String, calendar: Calendar) -> Int? {
        let symbols = calendar.weekdaySymbols.map { $0.lowercased() }
        if let index = symbols.firstIndex(of: name) { return index + 1 }
        let short = calendar.shortWeekdaySymbols.map { $0.lowercased() }
        if let index = short.firstIndex(of: name) { return index + 1 }
        return nil
    }

    private static func monthNumber(_ name: String) -> Int? {
        let months = [
            "january", "february", "march", "april", "may", "june", "july", "august",
            "september", "october", "november", "december"
        ]
        if let index = months.firstIndex(of: name) { return index + 1 }
        if let index = months.firstIndex(where: { $0.hasPrefix(name) && name.count >= 3 }) {
            return index + 1
        }
        return nil
    }

    /// How a resolved date reads in the picker's trailing column.
    static func detail(
        for date: Date, calendar: Calendar, includesTime: Bool = false
    ) -> String {
        var format = Date.FormatStyle(date: .abbreviated, time: .omitted)
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        let day = date.formatted(format)
        guard includesTime else { return day }
        var timeFormat = Date.FormatStyle(date: .omitted, time: .shortened)
        timeFormat.calendar = calendar
        timeFormat.timeZone = calendar.timeZone
        return day + "  " + date.formatted(timeFormat)
    }
}
