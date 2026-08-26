import Foundation

/// Natural-language date/time for the card. Four grammars; see docs/features/calculator.md.
enum CalcDateTime {
    /// Which occurrence of a bare, recurring date/time a phrase resolves to.
    private enum MomentBias { case future, past }

    static func evaluate(
        _ raw: String, now: Date = Date(), calendar: Calendar = .current
    )
        -> CalcResult?
    {
        let echo = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = echo.lowercased()
        guard !query.isEmpty else { return nil }

        // Cheap gate: our grammars always carry a connector, so app searches skip all the parsing.
        let hasUntil =
            query.contains(" till ") || query.contains(" until ") || query.contains(" til ")
        let hasSince = query.contains(" since ")
        let hasArith = query.contains(" + ") || query.contains(" - ")
        guard hasUntil || hasSince || hasArith else { return nil }

        if hasUntil, let result = parseUntil(query, echo: echo, now: now, calendar: calendar) {
            return result
        }
        if hasSince, let result = parseSince(query, echo: echo, now: now, calendar: calendar) {
            return result
        }
        if hasArith, let result = parseArithmetic(query, echo: echo, now: now, calendar: calendar) {
            return result
        }
        return nil
    }

    // MARK: - Grammar A: duration until a moment

    private static func parseUntil(
        _ query: String, echo: String, now: Date, calendar: Calendar
    )
        -> CalcResult?
    {
        guard let connector = [" until ", " till ", " til "].first(where: query.contains) else {
            return nil
        }
        let parts = query.components(separatedBy: connector)
        guard parts.count == 2,
            let unit = durationUnit(parts[0]),
            let moment = parseMoment(parts[1], now: now, calendar: calendar)
        else { return nil }

        let reference = unit.subDay ? now : calendar.startOfDay(for: now)
        let target = unit.subDay ? moment.date : calendar.startOfDay(for: moment.date)

        let value: Double
        switch unit.kind {
        case .day:
            value = Double(calendar.dateComponents([.day], from: reference, to: target).day ?? 0)
        case .week:
            let days = calendar.dateComponents([.day], from: reference, to: target).day ?? 0
            value = Double(days) / 7
        case .subSecond:
            value = target.timeIntervalSince(reference) / unit.seconds
        }

        let word = value == 1 ? unit.singular : unit.plural
        let source =
            unit.subDay
            ? timeString(now, calendar: calendar)
            : dateString(reference, now: now, calendar: calendar)
        let targetBadge =
            unit.subDay
            ? timeString(moment.date, calendar: calendar)
            : dateString(target, now: now, calendar: calendar)

        return CalcResult(
            expression: echo,
            sourceBadge: source,
            targetBadge: targetBadge,
            payload: .value(
                display: "\(CalcFormatter.display(value)) \(word)",
                copyText: "\(CalcFormatter.copyText(value)) \(word)"))
    }

    // MARK: - Grammar B: duration since a past moment

    private static func parseSince(
        _ query: String, echo: String, now: Date, calendar: Calendar
    )
        -> CalcResult?
    {
        let parts = query.components(separatedBy: " since ")
        guard parts.count == 2,
            let unit = durationUnit(parts[0]),
            let moment = parseMoment(parts[1], now: now, calendar: calendar, bias: .past)
        else { return nil }

        let reference = unit.subDay ? now : calendar.startOfDay(for: now)
        let past = unit.subDay ? moment.date : calendar.startOfDay(for: moment.date)

        let value: Double
        switch unit.kind {
        case .day:
            value = Double(calendar.dateComponents([.day], from: past, to: reference).day ?? 0)
        case .week:
            let days = calendar.dateComponents([.day], from: past, to: reference).day ?? 0
            value = Double(days) / 7
        case .subSecond:
            value = reference.timeIntervalSince(past) / unit.seconds
        }

        let word = value == 1 ? unit.singular : unit.plural
        let source =
            unit.subDay
            ? timeString(past, calendar: calendar)
            : dateString(past, now: now, calendar: calendar)
        let targetBadge =
            unit.subDay
            ? timeString(now, calendar: calendar)
            : dateString(reference, now: now, calendar: calendar)

        return CalcResult(
            expression: echo,
            sourceBadge: source,
            targetBadge: targetBadge,
            payload: .value(
                display: "\(CalcFormatter.display(value)) \(word)",
                copyText: "\(CalcFormatter.copyText(value)) \(word)"))
    }

    // MARK: - Grammars C & D: moment ± duration / moment − moment

    private static func parseArithmetic(
        _ query: String, echo: String, now: Date, calendar: Calendar
    ) -> CalcResult? {
        // Split on the earliest spaced operator; unspaced dashes (ISO dates, times) stay intact.
        let plus = query.range(of: " + ")
        let minus = query.range(of: " - ")
        let (opRange, op): (Range<String.Index>, Character)
        switch (plus, minus) {
        case (let p?, let m?): (opRange, op) = p.lowerBound < m.lowerBound ? (p, "+") : (m, "-")
        case (let p?, nil): (opRange, op) = (p, "+")
        case (nil, let m?): (opRange, op) = (m, "-")
        default: return nil
        }

        let left = String(query[..<opRange.lowerBound])
        let right = String(query[opRange.upperBound...])
        guard let base = parseMoment(left, now: now, calendar: calendar) else { return nil }

        // C: moment ± duration → a new moment.
        if let duration = parseDurationPhrase(right) {
            // Negating Int.min traps; degrade to no card on that edge.
            guard op == "+" || duration.count != .min else { return nil }
            let signed = op == "-" ? -duration.count : duration.count
            let resultDate: Date?
            switch duration.kind {
            case .component(let comp):
                resultDate = calendar.date(byAdding: comp, value: signed, to: base.date)
            case .businessDays:
                resultDate = addBusinessDays(signed, to: base.date, calendar: calendar)
            }
            guard let result = resultDate else { return nil }
            let hasTime = base.hasTime || duration.subDay
            let display = momentString(result, hasTime: hasTime, now: now, calendar: calendar)
            let sourceBadge = momentString(
                base.date, hasTime: base.hasTime, now: now, calendar: calendar)
            return CalcResult(
                expression: echo, sourceBadge: sourceBadge, targetBadge: "Result",
                payload: .value(display: display, copyText: display))
        }

        // D: moment − moment. Two letter-free operands (`5/2 - 1/2`) belong to the calculator.
        guard op == "-",
            left.contains(where: \.isLetter) || right.contains(where: \.isLetter),
            let other = parseMoment(right, now: now, calendar: calendar)
        else {
            return nil
        }
        let days =
            calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: other.date),
                to: calendar.startOfDay(for: base.date)
            ).day ?? 0
        let word = abs(days) == 1 ? "day" : "days"
        return CalcResult(
            expression: echo,
            sourceBadge: dateString(base.date, now: now, calendar: calendar),
            targetBadge: dateString(other.date, now: now, calendar: calendar),
            payload: .value(display: "\(days) \(word)", copyText: "\(days) \(word)"))
    }

    // MARK: - Moment parsing

    private struct Moment {
        let date: Date
        /// True when the phrase named a clock time ("9am", "now") — drives the time badge.
        let hasTime: Bool
    }

    private static func parseMoment(
        _ phrase: String, now: Date, calendar: Calendar, bias: MomentBias = .future
    ) -> Moment? {
        let atoms = atomize(phrase)
        switch atoms.count {
        case 1:
            return parseSingle(atoms[0], now: now, calendar: calendar, bias: bias)
        case 2:
            return parsePair(atoms[0], atoms[1], now: now, calendar: calendar, bias: bias)
        case 3:
            return parseTriple(atoms[0], atoms[1], atoms[2], now: now, calendar: calendar)
        default:
            return nil
        }
    }

    private static func parseSingle(
        _ atom: String, now: Date, calendar: Calendar, bias: MomentBias
    ) -> Moment? {
        let sod = calendar.startOfDay(for: now)
        switch atom {
        case "now": return Moment(date: now, hasTime: true)
        case "today": return Moment(date: sod, hasTime: false)
        case "tomorrow":
            return shift(sod, days: 1, calendar: calendar).map { Moment(date: $0, hasTime: false) }
        case "yesterday":
            return shift(sod, days: -1, calendar: calendar).map { Moment(date: $0, hasTime: false) }
        case "noon": return clockMoment(hour: 12, minute: 0, now: now, calendar: calendar, bias: bias)
        case "midnight":
            return clockMoment(hour: 0, minute: 0, now: now, calendar: calendar, bias: bias)
        default: break
        }
        if let weekday = weekdayByName[atom] {
            return nextWeekday(
                weekday, offsetToFuture: false, past: bias == .past, now: now, calendar: calendar)
        }
        if let month = monthByName[atom] {
            return monthDayMoment(month: month, day: 1, now: now, calendar: calendar, bias: bias)
        }
        return parseDateAtom(atom, now: now, calendar: calendar, bias: bias)
    }

    private static func parsePair(
        _ a: String, _ b: String, now: Date, calendar: Calendar, bias: MomentBias
    ) -> Moment? {
        // number + month  /  month + number  →  a day in that month
        if let month = monthByName[b], let day = Int(a) {
            return monthDayMoment(month: month, day: day, now: now, calendar: calendar, bias: bias)
        }
        if let month = monthByName[a], let day = Int(b) {
            return monthDayMoment(month: month, day: day, now: now, calendar: calendar, bias: bias)
        }
        // clock + am/pm  →  a time today (or tomorrow if it has passed)
        if b == "am" || b == "pm", let (hour, minute) = parseClock(a) {
            guard (1...12).contains(hour) else { return nil }
            let adjusted = b == "pm" ? (hour % 12) + 12 : hour % 12
            return clockMoment(
                hour: adjusted, minute: minute, now: now, calendar: calendar, bias: bias)
        }
        // next / last  +  weekday or month
        if a == "next" || a == "last" {
            if let weekday = weekdayByName[b] {
                return nextWeekday(
                    weekday, offsetToFuture: a == "next", past: a == "last", now: now,
                    calendar: calendar)
            }
            if let month = monthByName[b] {
                return monthDayMoment(
                    month: month, day: 1, now: now, calendar: calendar,
                    bias: a == "last" ? .past : .future)
            }
        }
        return nil
    }

    private static func parseTriple(
        _ a: String, _ b: String, _ c: String, now: Date, calendar: Calendar
    ) -> Moment? {
        // month day year (e.g. august 26 2026)
        if let month = monthByName[a], let day = Int(b), let year = Int(c), year > 31 {
            if let date = makeDate(fullYear(year), month, day, calendar) {
                return Moment(date: date, hasTime: false)
            }
        }
        // day month year (e.g. 26 august 2026)
        if let day = Int(a), let month = monthByName[b], let year = Int(c), year > 31 {
            if let date = makeDate(fullYear(year), month, day, calendar) {
                return Moment(date: date, hasTime: false)
            }
        }
        // year month day (e.g. 2026 august 26)
        if let year = Int(a), year > 31, let month = monthByName[b], let day = Int(c) {
            if let date = makeDate(fullYear(year), month, day, calendar) {
                return Moment(date: date, hasTime: false)
            }
        }
        return nil
    }

    /// A lone numeric atom carrying its own separators: `14:00`, `2027-04-09`, `9/4`, `9/4/2027`.
    private static func parseDateAtom(
        _ atom: String, now: Date, calendar: Calendar, bias: MomentBias
    ) -> Moment? {
        if atom.contains(":") {
            guard let (hour, minute) = parseClock(atom) else { return nil }
            return clockMoment(hour: hour, minute: minute, now: now, calendar: calendar, bias: bias)
        }
        if atom.contains("-") {
            let parts = atom.split(separator: "-").map(String.init)
            guard parts.count == 3, let year = Int(parts[0]), year > 31,
                let month = Int(parts[1]), let day = Int(parts[2]),
                let date = makeDate(year, month, day, calendar)
            else { return nil }
            return Moment(date: date, hasTime: false)
        }
        if atom.contains("/") {
            let parts = atom.split(separator: "/").map(String.init)
            if parts.count == 2, let month = Int(parts[0]), let day = Int(parts[1]) {
                return monthDayMoment(
                    month: month, day: day, now: now, calendar: calendar, bias: bias)
            }
            if parts.count == 3, let month = Int(parts[0]), let day = Int(parts[1]),
                let year = Int(parts[2]), let date = makeDate(fullYear(year), month, day, calendar)
            {
                return Moment(date: date, hasTime: false)
            }
        }
        return nil
    }

    // MARK: - Moment builders

    private static func clockMoment(
        hour: Int, minute: Int, now: Date, calendar: Calendar, bias: MomentBias = .future
    ) -> Moment? {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        let sod = calendar.startOfDay(for: now)
        guard var date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: sod)
        else { return nil }
        switch bias {
        case .future:
            if date <= now, let next = shift(date, days: 1, calendar: calendar) { date = next }
        case .past:
            if date > now, let prev = shift(date, days: -1, calendar: calendar) { date = prev }
        }
        return Moment(date: date, hasTime: true)
    }

    /// The given day of `month`, resolved to the upcoming or most recent year by `bias`.
    private static func monthDayMoment(
        month: Int, day: Int, now: Date, calendar: Calendar, bias: MomentBias
    ) -> Moment? {
        let currentYear = calendar.component(.year, from: now)
        guard let current = makeDate(currentYear, month, day, calendar) else { return nil }
        switch bias {
        case .future:
            if current < calendar.startOfDay(for: now),
                let next = makeDate(currentYear + 1, month, day, calendar)
            {
                return Moment(date: next, hasTime: false)
            }
            return Moment(date: current, hasTime: false)
        case .past:
            if current > calendar.startOfDay(for: now),
                let prev = makeDate(currentYear - 1, month, day, calendar)
            {
                return Moment(date: prev, hasTime: false)
            }
            return Moment(date: current, hasTime: false)
        }
    }

    private static func nextWeekday(
        _ weekday: Int, offsetToFuture: Bool, past: Bool, now: Date, calendar: Calendar
    ) -> Moment? {
        let sod = calendar.startOfDay(for: now)
        let today = calendar.component(.weekday, from: sod)
        if past {
            var back = (today - weekday + 7) % 7
            if back == 0 { back = 7 }
            return shift(sod, days: -back, calendar: calendar).map {
                Moment(date: $0, hasTime: false)
            }
        }
        var ahead = (weekday - today + 7) % 7
        if ahead == 0 && offsetToFuture { ahead = 7 }
        return shift(sod, days: ahead, calendar: calendar).map { Moment(date: $0, hasTime: false) }
    }

    // MARK: - Durations

    private enum DurKind { case subSecond, day, week }

    private struct DurUnit {
        let seconds: Double
        let singular: String
        let plural: String
        let kind: DurKind
        var subDay: Bool { kind == .subSecond }
    }

    private static func durationUnit(_ phrase: String) -> DurUnit? {
        guard let last = phrase.split(separator: " ").last.map(String.init) else { return nil }
        switch last {
        case "s", "sec", "secs", "second", "seconds":
            return DurUnit(seconds: 1, singular: "second", plural: "seconds", kind: .subSecond)
        case "min", "mins", "minute", "minutes":
            return DurUnit(seconds: 60, singular: "minute", plural: "minutes", kind: .subSecond)
        case "h", "hr", "hrs", "hour", "hours":
            return DurUnit(seconds: 3600, singular: "hour", plural: "hours", kind: .subSecond)
        case "d", "day", "days":
            return DurUnit(seconds: 86400, singular: "day", plural: "days", kind: .day)
        case "wk", "week", "weeks":
            return DurUnit(seconds: 604800, singular: "week", plural: "weeks", kind: .week)
        default:
            return nil
        }
    }

    private enum DurationKind {
        case component(Calendar.Component)
        case businessDays
    }

    private struct DurationPhrase {
        let count: Int
        let kind: DurationKind
        let subDay: Bool
    }

    /// `<n> <unit>` for date arithmetic; weeks fold to days so `date(byAdding:)` stays DST-safe.
    private static func parseDurationPhrase(_ phrase: String) -> DurationPhrase? {
        let atoms = atomize(phrase)
        if atoms.count == 2, let count = Int(atoms[0]) {
            switch atoms[1] {
            case "s", "sec", "secs", "second", "seconds":
                return DurationPhrase(count: count, kind: .component(.second), subDay: true)
            case "min", "mins", "minute", "minutes":
                return DurationPhrase(count: count, kind: .component(.minute), subDay: true)
            case "h", "hr", "hrs", "hour", "hours":
                return DurationPhrase(count: count, kind: .component(.hour), subDay: true)
            case "d", "day", "days":
                return DurationPhrase(count: count, kind: .component(.day), subDay: false)
            case "wk", "week", "weeks":
                // Absurd counts overflow the fold to days; degrade to no card rather than trap.
                let (days, overflow) = count.multipliedReportingOverflow(by: 7)
                return overflow ? nil : DurationPhrase(count: days, kind: .component(.day), subDay: false)
            case "weekday", "weekdays", "workday", "workdays":
                return DurationPhrase(count: count, kind: .businessDays, subDay: false)
            default: return nil
            }
        } else if atoms.count == 3, let count = Int(atoms[0]) {
            let unit = "\(atoms[1]) \(atoms[2])"
            if unit == "business day" || unit == "business days" ||
               unit == "work day" || unit == "work days" {
                return DurationPhrase(count: count, kind: .businessDays, subDay: false)
            }
        }
        return nil
    }

    private static func addBusinessDays(_ count: Int, to base: Date, calendar: Calendar) -> Date? {
        guard count != 0 else { return base }
        let step = count > 0 ? 1 : -1
        let target = abs(count)
        var added = 0
        var current = calendar.startOfDay(for: base)

        var iterations = 0
        while added < target && iterations < 100_000 {
            iterations += 1
            guard let next = calendar.date(byAdding: .day, value: step, to: current) else { return nil }
            current = next
            let weekday = calendar.component(.weekday, from: current)
            // 1 is Sunday, 7 is Saturday
            if weekday != 1 && weekday != 7 {
                added += 1
            }
        }
        return current
    }

    // MARK: - Formatting

    private static func momentString(
        _ date: Date, hasTime: Bool, now: Date, calendar: Calendar
    )
        -> String
    {
        let day = dateString(date, now: now, calendar: calendar)
        return hasTime ? "\(day) at \(timeString(date, calendar: calendar))" : day
    }

    private static func dateString(_ date: Date, now: Date, calendar: Calendar) -> String {
        let sameYear =
            calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return format(
            date, calendar: calendar, pattern: sameYear ? "EEEE, d MMMM" : "EEEE, d MMMM, yyyy")
    }

    private static func timeString(_ date: Date, calendar: Calendar) -> String {
        format(date, calendar: calendar, pattern: "h:mm a")
    }

    private static func format(_ date: Date, calendar: Calendar, pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        // Follow the injected calendar's locale so weekday/month names match the user's language.
        formatter.locale = calendar.locale ?? Locale(identifier: "en_US")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    // MARK: - Low-level helpers

    /// Split into letter-runs and number-runs; ":", "/", "-", "." stay inside a number-run.
    private static func atomize(_ text: String) -> [String] {
        var atoms: [String] = []
        var current = ""
        var currentIsNumber = false
        func flush() {
            if !current.isEmpty { atoms.append(current) }
            current = ""
        }
        for ch in text {
            if ch == " " {
                flush()
                continue
            }
            let isNumeric = ch.isNumber || ch == ":" || ch == "/" || ch == "-" || ch == "."
            let isLetter = ch.isLetter
            if current.isEmpty {
                current.append(ch)
                currentIsNumber = isNumeric && !isLetter
            } else if isLetter && currentIsNumber {
                flush()
                current.append(ch)
                currentIsNumber = false
            } else if isNumeric && !isLetter && !currentIsNumber {
                flush()
                current.append(ch)
                currentIsNumber = true
            } else {
                current.append(ch)
            }
        }
        flush()
        return atoms
    }

    private static func parseClock(_ atom: String) -> (hour: Int, minute: Int)? {
        if atom.contains(":") {
            let parts = atom.split(separator: ":").map(String.init)
            guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else {
                return nil
            }
            return (hour, minute)
        }
        guard let hour = Int(atom) else { return nil }
        return (hour, 0)
    }

    private static func makeDate(
        _ year: Int, _ month: Int, _ day: Int, _ calendar: Calendar
    )
        -> Date?
    {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components),
            calendar.component(.day, from: date) == day,
            calendar.component(.month, from: date) == month
        else { return nil }
        return date
    }

    private static func shift(_ date: Date, days: Int, calendar: Calendar) -> Date? {
        calendar.date(byAdding: .day, value: days, to: date)
    }

    /// Expand a 2-digit year the way date pickers do; 4-digit years pass through.
    private static func fullYear(_ year: Int) -> Int {
        if year >= 100 { return year }
        return year <= 68 ? 2000 + year : 1900 + year
    }

    private static let monthByName: [String: Int] = [
        "january": 1, "jan": 1, "february": 2, "feb": 2, "march": 3, "mar": 3, "april": 4,
        "apr": 4, "may": 5, "june": 6, "jun": 6, "july": 7, "jul": 7, "august": 8, "aug": 8,
        "september": 9, "sep": 9, "sept": 9, "october": 10, "oct": 10, "november": 11, "nov": 11,
        "december": 12, "dec": 12
    ]

    /// Gregorian weekday numbers (Sunday = 1).
    private static let weekdayByName: [String: Int] = [
        "sunday": 1, "sun": 1, "monday": 2, "mon": 2, "tuesday": 3, "tue": 3, "tues": 3,
        "wednesday": 4, "wed": 4, "thursday": 5, "thu": 5, "thurs": 5, "friday": 6, "fri": 6,
        "saturday": 7, "sat": 7
    ]
}
