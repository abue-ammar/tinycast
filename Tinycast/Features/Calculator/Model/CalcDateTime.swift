import Foundation

/// Natural-language date/time for the card. Four grammars; see docs/features/calculator.md.
enum CalcDateTime {
    /// Which occurrence of a bare, recurring date/time a phrase resolves to.
    private enum MomentBias { case future, past, nearest }

    static func evaluate(
        _ raw: String, now: Date = Date(), calendar: Calendar = .current
    )
        -> CalcResult?
    {
        let echo = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = echo.lowercased()
        guard !query.isEmpty else { return nil }

        // One pass over the words, since an app search pays this on every keystroke.
        let signals = keywordSignals(query)
        let hasDigit = signals.contains(.digit)
        let hasUntil = signals.contains(.until)
        let hasSince = signals.contains(.since)
        let hasArith = signals.contains(.arithmetic)
        let hasFromAgo = signals.contains(.fromAgo)
        let hasIn = signals.contains(.inWord)
        // A named moment needs a qualifier: a lone `tomorrow` is an app search.
        let isBareMoment =
            signals.contains(.at) || signals.contains(.nextOrLast)
            || (hasDigit && namesADay(query))
        guard hasUntil || hasSince || hasArith || hasFromAgo || hasIn || isBareMoment else {
            return nil
        }

        if hasUntil, let result = parseUntil(query, echo: echo, now: now, calendar: calendar) {
            return result
        }
        if hasSince, let result = parseSince(query, echo: echo, now: now, calendar: calendar) {
            return result
        }
        if hasArith, let result = parseArithmetic(query, echo: echo, now: now, calendar: calendar) {
            return result
        }
        if hasFromAgo, let result = parseOffset(query, echo: echo, now: now, calendar: calendar) {
            return result
        }
        if hasIn, let result = parseWeekdayIn(query, echo: echo, now: now, calendar: calendar) {
            return result
        }
        if isBareMoment, let result = bareMoment(query, echo: echo, now: now, calendar: calendar) {
            return result
        }
        return nil
    }

    private struct Signals: OptionSet {
        let rawValue: Int
        static let digit = Signals(rawValue: 1 << 0)
        static let until = Signals(rawValue: 1 << 1)
        static let since = Signals(rawValue: 1 << 2)
        static let arithmetic = Signals(rawValue: 1 << 3)
        static let fromAgo = Signals(rawValue: 1 << 4)
        static let inWord = Signals(rawValue: 1 << 5)
        static let at = Signals(rawValue: 1 << 6)
        static let nextOrLast = Signals(rawValue: 1 << 7)
    }

    /// One walk of the query, so the gate costs a single pass rather than ten substring scans.
    private static func keywordSignals(_ query: String) -> Signals {
        var signals: Signals = []
        var word = ""
        var index = 0
        var isFirst = true

        func classify(_ word: String, isFirst: Bool, isLast: Bool) {
            switch word {
            case "till", "until", "til": if !isFirst, !isLast { signals.insert(.until) }
            case "since": if !isFirst, !isLast { signals.insert(.since) }
            case "+", "-": if !isFirst, !isLast { signals.insert(.arithmetic) }
            case "from": if !isFirst, !isLast { signals.insert(.fromAgo) }
            case "ago": if !isFirst { signals.insert(.fromAgo) }
            case "in": if !isFirst, !isLast { signals.insert(.inWord) }
            case "at": if !isFirst, !isLast { signals.insert(.at) }
            case "next", "last": if isFirst { signals.insert(.nextOrLast) }
            default: break
            }
        }

        for character in query {
            if character.isNumber { signals.insert(.digit) }
            if character.isWhitespace {
                classify(word, isFirst: isFirst, isLast: false)
                isFirst = isFirst && word.isEmpty
                if !word.isEmpty { isFirst = false }
                word = ""
            } else {
                word.append(character)
            }
            index += 1
        }
        classify(word, isFirst: isFirst, isLast: true)
        return signals
    }

    /// A day number beside a month, which no app search looks like — `25. aug`, `aug 25`.
    private static func namesADay(_ query: String) -> Bool {
        let atoms = atomize(query)
        guard atoms.count == 2 || atoms.count == 3 else { return atoms.count == 1 && isDottedDate(atoms) }
        let months = atoms.filter { monthByName[$0] != nil }.count
        let days = atoms.filter { ordinalDay($0) != nil }.count
        return months == 1 && days == atoms.count - 1
    }

    /// `25.8.27` on its own: three dotted parts, which cannot be read as one number.
    private static func isDottedDate(_ atoms: [String]) -> Bool {
        guard let only = atoms.first else { return false }
        let parts = only.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[2].count == 2 || parts[2].count == 4 else { return false }
        return parts.allSatisfy { Int($0) != nil }
    }

    /// `next monday`, `tomorrow`, `tomorrow at 9am` — a moment named without any arithmetic.
    private static func bareMoment(
        _ query: String, echo: String, now: Date, calendar: Calendar
    ) -> CalcResult? {
        var phrase = query
        var clock: (hour: Int, minute: Int)?
        // `at 9am` rides along, so the answer keeps the time it was given.
        if let range = phrase.range(of: " at ") {
            let tail = String(phrase[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard let parsed = parseMeridiemClock(tail) else { return nil }
            clock = parsed
            phrase = String(phrase[..<range.lowerBound])
        }
        // No `till` or `since` to lean on, so a bare date takes the year it is nearest.
        guard let moment = parseMoment(phrase, now: now, calendar: calendar, bias: .nearest)
        else { return nil }

        var date = moment.date
        var hasTime = moment.hasTime
        if let clock {
            guard
                let set = calendar.date(
                    bySettingHour: clock.hour, minute: clock.minute, second: 0, of: date)
            else { return nil }
            date = set
            hasTime = true
        }

        return CalcResult(
            expression: echo,
            sourceBadge: dateString(now, now: now, calendar: calendar),
            targetBadge: weekdayName(date, calendar: calendar),
            payload: .value(
                display: answerString(date, hasTime: hasTime, now: now, calendar: calendar),
                copyText: answerString(date, hasTime: hasTime, now: now, calendar: calendar)))
    }

    /// `9am`, `5:30pm`, `14:00` as a wall clock, with no bias applied.
    private static func parseMeridiemClock(_ text: String) -> (hour: Int, minute: Int)? {
        var body = text
        var meridiem: String?
        for suffix in ["am", "pm"] where body.hasSuffix(suffix) {
            meridiem = suffix
            body.removeLast(2)
        }
        body = body.trimmingCharacters(in: .whitespaces)
        guard let (hour, minute) = parseClock(body) else { return nil }
        guard let meridiem else {
            return (0...23).contains(hour) ? (hour, minute) : nil
        }
        guard (1...12).contains(hour) else { return nil }
        return (meridiem == "pm" ? (hour % 12) + 12 : hour % 12, minute)
    }

    /// `monday in 3 weeks` — that weekday, in the week the duration lands in.
    private static func parseWeekdayIn(
        _ query: String, echo: String, now: Date, calendar: Calendar
    ) -> CalcResult? {
        guard let range = query.range(of: " in ") else { return nil }
        let head = String(query[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        guard let weekday = weekdayByName[head],
            let duration = parseDurationPhrase(String(query[range.upperBound...])),
            !duration.subDay, !duration.businessDays,
            let landing = calendar.date(
                byAdding: duration.component, value: duration.count,
                to: calendar.startOfDay(for: now))
        else { return nil }

        // The weekday inside the landing week, so `monday in 3 weeks` is that week's Monday.
        guard let week = calendar.dateInterval(of: .weekOfYear, for: landing),
            let result = shift(
                week.start, days: (weekday - calendar.firstWeekday + 7) % 7, calendar: calendar)
        else { return nil }

        return CalcResult(
            expression: echo,
            sourceBadge: dateString(now, now: now, calendar: calendar),
            targetBadge: weekdayName(result, calendar: calendar),
            payload: .value(
                display: answerString(result, hasTime: false, now: now, calendar: calendar),
                copyText: answerString(result, hasTime: false, now: now, calendar: calendar)))
    }

    /// `5 weekdays from now`, `3 days from today`, `2 weeks ago` — the duration leads.
    private static func parseOffset(
        _ query: String, echo: String, now: Date, calendar: Calendar
    ) -> CalcResult? {
        let durationText: String
        let anchorText: String
        let sign: Int
        if let range = query.range(of: " from ") {
            durationText = String(query[..<range.lowerBound])
            anchorText = String(query[range.upperBound...])
            sign = 1
        } else if query.hasSuffix(" ago") {
            durationText = String(query.dropLast(4))
            anchorText = "today"
            sign = -1
        } else {
            return nil
        }

        guard let duration = parseDurationPhrase(durationText), duration.count != .min,
            let anchor = parseMoment(anchorText, now: now, calendar: calendar)
        else { return nil }

        let signed = duration.count * sign
        let shifted =
            duration.businessDays
            ? addBusinessDays(signed, to: anchor.date, calendar: calendar)
            : calendar.date(byAdding: duration.component, value: signed, to: anchor.date)
        guard let result = shifted else { return nil }

        let hasTime = anchor.hasTime && duration.subDay
        let display = answerString(result, hasTime: hasTime, now: now, calendar: calendar)
        return CalcResult(
            expression: echo,
            sourceBadge: momentString(
                anchor.date, hasTime: hasTime, now: now, calendar: calendar),
            targetBadge: weekdayName(result, calendar: calendar),
            payload: .value(
                display: display, copyText: display))
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
        // Nearest year for a shifted moment; a measured one keeps the forward bias.
        let shifts =
            parseDurationPhrase(right) != nil || Int(right.trimmingCharacters(in: .whitespaces)) != nil
        guard
            let base = parseMoment(
                left, now: now, calendar: calendar, bias: shifts ? .nearest : .future)
        else { return nil }

        // C: moment ± duration, chained left to right — every term after the first shifts again.
        if let shifted = applyShifts(op, right, to: base, calendar: calendar) {
            let display = answerString(
                shifted.date, hasTime: shifted.hasTime, now: now, calendar: calendar)
            return CalcResult(
                expression: echo,
                sourceBadge: momentString(
                    base.date, hasTime: base.hasTime, now: now, calendar: calendar),
                targetBadge: weekdayName(shifted.date, calendar: calendar),
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

    /// Nil unless every term is a duration, so grammar D still sees a trailing moment.
    private static func applyShifts(
        _ firstOperator: Character, _ tail: String, to base: Moment, calendar: Calendar
    ) -> Moment? {
        var moment = base
        var op = firstOperator
        var rest = Substring(tail)

        while true {
            let (term, nextOperator, remainder) = splitTerm(rest)
            guard let shifted = shift(moment, by: term, op: op, calendar: calendar) else {
                return nil
            }
            moment = shifted
            guard let nextOperator else { return moment }
            op = nextOperator
            rest = remainder
        }
    }

    /// The text up to the next spaced `+` / `-`, that operator, and whatever follows it.
    private static func splitTerm(
        _ text: Substring
    ) -> (term: String, nextOperator: Character?, remainder: Substring) {
        let plus = text.range(of: " + ")
        let minus = text.range(of: " - ")
        let next: (Range<Substring.Index>, Character)?
        switch (plus, minus) {
        case (let p?, let m?): next = p.lowerBound < m.lowerBound ? (p, "+") : (m, "-")
        case (let p?, nil): next = (p, "+")
        case (nil, let m?): next = (m, "-")
        default: next = nil
        }
        guard let (range, op) = next else { return (String(text), nil, text) }
        return (String(text[..<range.lowerBound]), op, text[range.upperBound...])
    }

    /// One term against a moment: a spelled duration, or a bare number in the moment's own unit.
    private static func shift(
        _ moment: Moment, by term: String, op: Character, calendar: Calendar
    ) -> Moment? {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        if let count = Int(trimmed) {
            // Negating Int.min traps; degrade to no card on that edge.
            guard op == "+" || count != .min else { return nil }
            let component: Calendar.Component = moment.hasTime ? .hour : .day
            guard
                let date = calendar.date(
                    byAdding: component, value: op == "-" ? -count : count, to: moment.date)
            else { return nil }
            return Moment(date: date, hasTime: moment.hasTime)
        }

        guard let duration = parseDurationPhrase(trimmed), op == "+" || duration.count != .min
        else { return nil }
        let signed = op == "-" ? -duration.count : duration.count
        let date =
            duration.businessDays
            ? addBusinessDays(signed, to: moment.date, calendar: calendar)
            : calendar.date(byAdding: duration.component, value: signed, to: moment.date)
        guard let date else { return nil }
        return Moment(date: date, hasTime: moment.hasTime || duration.subDay)
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
            return parseTriple(atoms[0], atoms[1], atoms[2], calendar: calendar)
        default:
            return nil
        }
    }

    /// `august 26 2026` / `26 august 2026` — a month name with both a day and a year.
    private static func parseTriple(
        _ a: String, _ b: String, _ c: String, calendar: Calendar
    ) -> Moment? {
        guard let year = Int(c) else { return nil }
        let month: Int
        let day: Int
        if let named = monthByName[a], let value = ordinalDay(b) {
            (month, day) = (named, value)
        } else if let named = monthByName[b], let value = ordinalDay(a) {
            (month, day) = (named, value)
        } else {
            return nil
        }
        guard let date = makeDate(fullYear(year), month, day, calendar) else { return nil }
        return Moment(date: date, hasTime: false)
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
        if let month = monthByName[b], let day = ordinalDay(a) {
            return monthDayMoment(month: month, day: day, now: now, calendar: calendar, bias: bias)
        }
        if let month = monthByName[a], let day = ordinalDay(b) {
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
        // Dotted dates are day-first: `19.2.27` is 19 February, and the tail rejects versions.
        if atom.contains(".") {
            let parts = atom.split(separator: ".").map(String.init)
            guard parts.count == 3, let day = Int(parts[0]), let month = Int(parts[1]),
                let year = Int(parts[2]), parts[2].count == 2 || parts[2].count == 4,
                let date = makeDate(fullYear(year), month, day, calendar)
            else { return nil }
            return Moment(date: date, hasTime: false)
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
        case .nearest:
            break
        }
        return Moment(date: date, hasTime: true)
    }

    /// The given day of `month`, resolved to the upcoming, most recent, or nearest year by `bias`.
    private static func monthDayMoment(
        month: Int, day: Int, now: Date, calendar: Calendar, bias: MomentBias = .future
    ) -> Moment? {
        let year = calendar.component(.year, from: now)
        guard let thisYear = makeDate(year, month, day, calendar) else { return nil }
        let sod = calendar.startOfDay(for: now)
        switch bias {
        case .future:
            if thisYear >= sod { return Moment(date: thisYear, hasTime: false) }
            guard let nextYear = makeDate(year + 1, month, day, calendar) else { return nil }
            return Moment(date: nextYear, hasTime: false)
        case .past:
            if thisYear <= sod { return Moment(date: thisYear, hasTime: false) }
            guard let lastYear = makeDate(year - 1, month, day, calendar) else { return nil }
            return Moment(date: lastYear, hasTime: false)
        // A date days behind is likelier the one meant than the same date a year out.
        case .nearest:
            return Moment(date: thisYear, hasTime: false)
        }
    }

    private static func nextWeekday(
        _ weekday: Int, offsetToFuture: Bool, past: Bool = false, now: Date, calendar: Calendar
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

    private struct DurationPhrase {
        let count: Int
        let component: Calendar.Component
        let subDay: Bool
        /// Weekend days are skipped rather than counted, so the result lands Mon–Fri.
        var businessDays = false
    }

    /// `<n> <unit>` for date arithmetic; weeks fold to days so `date(byAdding:)` stays DST-safe.
    private static func parseDurationPhrase(_ phrase: String) -> DurationPhrase? {
        let atoms = atomize(phrase)
        // "business days" / "work days" are two atoms after the count, one word or two.
        if atoms.count >= 2, let count = Int(atoms[0]),
            businessDayPhrases.contains(atoms.dropFirst().joined())
        {
            return DurationPhrase(count: count, component: .day, subDay: false, businessDays: true)
        }
        guard atoms.count == 2, let count = Int(atoms[0]) else { return nil }
        switch atoms[1] {
        case "s", "sec", "secs", "second", "seconds":
            return DurationPhrase(count: count, component: .second, subDay: true)
        case "min", "mins", "minute", "minutes":
            return DurationPhrase(count: count, component: .minute, subDay: true)
        case "h", "hr", "hrs", "hour", "hours":
            return DurationPhrase(count: count, component: .hour, subDay: true)
        case "d", "day", "days":
            return DurationPhrase(count: count, component: .day, subDay: false)
        case "wk", "week", "weeks":
            // Absurd counts overflow the fold to days; degrade to no card rather than trap.
            let (days, overflow) = count.multipliedReportingOverflow(by: 7)
            return overflow ? nil : DurationPhrase(count: days, component: .day, subDay: false)
        default: return nil
        }
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

    /// The weekday moves to the badge, so an answered moment leads with the date itself.
    private static func answerString(
        _ date: Date, hasTime: Bool, now: Date, calendar: Calendar
    ) -> String {
        let sameYear =
            calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let day = format(
            date, calendar: calendar, pattern: sameYear ? "d MMMM" : "d MMMM, yyyy")
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

    /// The answer's own weekday, which the date itself never spells out.
    private static func weekdayName(_ date: Date, calendar: Calendar) -> String {
        format(date, calendar: calendar, pattern: "EEEE")
    }

    private static func format(_ date: Date, calendar: Calendar, pattern: String) -> String {
        CalcDateFormatters.string(from: date, calendar: calendar, zone: calendar.timeZone, pattern: pattern)
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

    /// A day number, with the ordinal dot German and Austrian dates write: `28. aug`.
    private static func ordinalDay(_ atom: String) -> Int? {
        Int(atom.hasSuffix(".") ? String(atom.dropLast()) : atom)
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

    /// Steps day by day, counting only Mon–Fri. Public holidays are deliberately not modelled.
    private static func addBusinessDays(_ count: Int, to date: Date, calendar: Calendar) -> Date? {
        guard abs(count) <= 10_000 else { return nil }
        let step = count < 0 ? -1 : 1
        var remaining = abs(count)
        var cursor = date
        while remaining > 0 {
            guard let next = shift(cursor, days: step, calendar: calendar) else { return nil }
            cursor = next
            if !isWeekend(cursor, calendar: calendar) { remaining -= 1 }
        }
        return cursor
    }

    private static func isWeekend(_ date: Date, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
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

    private static let businessDayPhrases: Set<String> = [
        "businessday", "businessdays", "workday", "workdays", "workingday", "workingdays",
        "weekday", "weekdays"
    ]

    /// Gregorian weekday numbers (Sunday = 1).
    private static let weekdayByName: [String: Int] = [
        "sunday": 1, "sun": 1, "monday": 2, "mon": 2, "tuesday": 3, "tue": 3, "tues": 3,
        "wednesday": 4, "wed": 4, "thursday": 5, "thu": 5, "thurs": 5, "friday": 6, "fri": 6,
        "saturday": 7, "sat": 7
    ]
}
