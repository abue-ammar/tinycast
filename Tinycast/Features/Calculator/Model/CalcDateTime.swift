import Foundation

enum CalcDateTime {
    private enum MomentBias { case future, past, nearest }

    static func evaluate(
        _ raw: String, now: Date, calendar: Calendar
    )
        -> CalcResult?
    {
        let echo = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var lowered = fromNow(withoutApostrophes(echo.lowercased()))
        guard !lowered.isEmpty else { return nil }

        // One pass over the words, since an app search pays this on every keystroke.
        let signals = keywordSignals(lowered)
        if signals.contains(.synonym) { lowered = canonicalWords(lowered) }
        let hasDigit = signals.contains(.digit)
        let hasUntil = signals.contains(.until)
        let hasSince = signals.contains(.since)
        let hasArith = signals.contains(.arithmetic) && signals.contains(.moment)
        let hasFromAgo = signals.contains(.fromAgo)
        let hasIn = signals.contains(.inWord)
        let hasTimestamp = signals.contains(.timestamp)
        let hasSpan = signals.contains(.span) && signals.contains(.moment)
        // A named moment needs a qualifier: a lone `tomorrow` is an app search.
        let isBareMoment =
            signals.contains(.at) || signals.contains(.nextOrLast)
            || (hasDigit && signals.contains(.moment) && holidayYear(lowered) != nil)
            || (hasDigit && signals.contains(.dayName) && namesADay(lowered))
            || CalcTimestamp.looksLikeISO(lowered) || namesBoundary(lowered)
        guard
            hasUntil || hasSince || hasArith || hasFromAgo || hasIn || isBareMoment || hasTimestamp || hasSpan
        else {
            return nil
        }

        let query = lowered.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if hasTimestamp || query.hasSuffix(" to date") && CalcTimestamp.looksLikeISO(query),
            let result = parseTimestamp(query, echo: echo, now: now, calendar: calendar)
        {
            return result
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
        if hasSpan, let result = parseSpan(query, echo: echo, now: now, calendar: calendar) {
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

    /// The only lone words that answer: each names one moment, where `monday` or `july` recurs.
    static func namedMoment(_ word: String, now: Date, calendar: Calendar) -> CalcResult? {
        let lowered = word.lowercased()
        switch lowered {
        case "now", "today", "tomorrow", "yesterday":
            return bareMoment(lowered, echo: word, now: now, calendar: calendar)
        case "time":
            let clock = CalcDateFormatters.string(
                from: now, calendar: calendar, zone: calendar.timeZone, template: "jmm")
            return CalcResult(
                expression: word,
                sourceBadge: dateString(now, now: now, calendar: calendar),
                targetBadge: CalcTimeZone.label(for: calendar.timeZone),
                payload: .value(display: clock, copyText: clock))
        default:
            return nil
        }
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
        static let timestamp = Signals(rawValue: 1 << 8)
        static let moment = Signals(rawValue: 1 << 9)
        static let dayName = Signals(rawValue: 1 << 10)
        static let span = Signals(rawValue: 1 << 11)
        static let synonym = Signals(rawValue: 1 << 12)
    }

    /// `in 3 days` is `3 days from now`; an `in` that leads anything but a duration is left alone.
    private static func fromNow(_ query: String) -> String {
        guard query.hasPrefix("in ") else { return query }
        let rest = String(query.dropFirst(3))
        return parseDurations(rest) == nil ? query : rest + " from now"
    }

    private static func canonicalWords(_ query: String) -> String {
        query.replacingOccurrences(of: "a.m.", with: "am").replacingOccurrences(of: "p.m.", with: "pm")
            .split(separator: " ", omittingEmptySubsequences: false)
            .map { synonyms[String($0)] ?? String($0) }.joined(separator: " ")
    }

    private static let synonyms = ["previous": "last", "midday": "noon"]

    private struct Boundary {
        let atEnd: Bool
        let offset: Int
        let period: Calendar.Component
    }

    /// `end of month`, `start of next year`: a period's edge names one day, so it needs no other signal.
    private static func boundary(_ query: String) -> Boundary? {
        var words = query.split(separator: " ").map(String.init)
        words.removeAll { $0 == "the" }
        let heads = ["end": true, "start": false, "beginning": false]
        guard words.count >= 3, let atEnd = heads[words[0]], words[1] == "of" else { return nil }
        words.removeFirst(2)
        let offsets = ["next": 1, "last": -1, "this": 0]
        let offset = offsets[words[0]] ?? 0
        if offsets[words[0]] != nil { words.removeFirst() }
        guard words.count == 1, let period = ["month": Calendar.Component.month, "year": .year][words[0]]
        else { return nil }
        return Boundary(atEnd: atEnd, offset: offset, period: period)
    }

    private static func namesBoundary(_ query: String) -> Bool {
        (query.hasPrefix("end ") || query.hasPrefix("start ") || query.hasPrefix("beginning "))
            && boundary(query) != nil
    }

    private static func boundaryDate(_ edge: Boundary, now: Date, calendar: Calendar) -> Date? {
        guard
            let anchor = calendar.date(
                byAdding: edge.period, value: edge.offset, to: calendar.startOfDay(for: now)),
            let interval = calendar.dateInterval(of: edge.period, for: anchor)
        else { return nil }
        return edge.atEnd ? shift(interval.end, days: -1, calendar: calendar) : interval.start
    }

    private static func keywordSignals(_ query: String) -> Signals {
        var signals: Signals = []
        let words = query.split(whereSeparator: \.isWhitespace)
        for (index, word) in words.enumerated() {
            let isFirst = index == 0
            let isLast = index == words.count - 1
            switch word {
            case "till", "until", "til": if !isFirst, !isLast { signals.insert(.until) }
            case "since": if !isFirst, !isLast { signals.insert(.since) }
            case "+", "-": if !isFirst, !isLast { signals.insert(.arithmetic) }
            case "from", "after", "before": if !isFirst, !isLast { signals.insert(.fromAgo) }
            case "to", "through", "between": if !isLast { signals.insert(.span) }
            case "ago": if !isFirst { signals.insert(.fromAgo) }
            case "in": if !isFirst, !isLast { signals.insert(.inWord) }
            case "at": if !isFirst, !isLast { signals.insert(.at) }
            case "new":
                if index + 1 < words.count, words[index + 1].hasPrefix("year") { signals.insert(.moment) }
            case "next", "last", "this": if isFirst { signals.insert(.nextOrLast) }
            case "previous":
                signals.insert(.synonym)
                if isFirst { signals.insert(.nextOrLast) }
            case "midday": signals.formUnion([.synonym, .moment])
            case "unix", "timestamp": signals.formUnion([.timestamp, .moment])
            case "date", "iso", "iso8601":
                if isLast, index > 0, words[index - 1] == "to" { signals.insert(.timestamp) }
            default: break
            }
            var dots = 0
            var dashes = 0
            for byte in word.utf8 {
                if (48...57).contains(byte) { signals.insert(.digit) }
                if byte == 46 { dots += 1 }
                if byte == 45 { dashes += 1 }
                if byte == 58 || byte == 47 { signals.insert(.moment) }
            }
            if dots >= 2 {
                signals.formUnion([.dayName, .moment])
                if word.hasSuffix(".m.") { signals.insert(.synonym) }
            }
            if dashes >= 2 { signals.insert(.moment) }
            for letters in word.utf8.split(whereSeparator: { !(97...122).contains($0) }) {
                let name = String(bytes: letters, encoding: .utf8)!
                if monthByName[name] != nil { signals.formUnion([.dayName, .moment]) }
                if weekdayByName[name] != nil { signals.insert(.moment) }
                switch name {
                case "now", "today", "tomorrow", "yesterday", "noon", "midnight", "am", "pm":
                    signals.insert(.moment)
                default:
                    if CalcHolidays.signalWords.contains(name) { signals.insert(.moment) }
                }
            }
        }
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
        guard let moment = parseMoment(query, now: now, calendar: calendar, bias: .nearest)
        else { return nil }
        let date = moment.date
        let hasTime = moment.hasTime
        let text = answerString(date, hasTime: hasTime, now: now, calendar: calendar)
        return CalcResult(
            expression: echo,
            sourceBadge: dateString(now, now: now, calendar: calendar),
            targetBadge: weekdayName(date, calendar: calendar),
            payload: .value(display: text, copyText: text))
    }

    /// `9am`, `5:30pm`, `14:00` as a wall clock, with no bias applied.
    private static func parseMeridiemClock(_ text: String) -> (hour: Int, minute: Int)? {
        if text == "noon" { return (12, 0) }
        if text == "midnight" { return (0, 0) }
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
            let durations = parseDurations(String(query[range.upperBound...])),
            durations.count == 1, let duration = durations.first,
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

        let text = answerString(result, hasTime: false, now: now, calendar: calendar)
        return CalcResult(
            expression: echo,
            sourceBadge: dateString(now, now: now, calendar: calendar),
            targetBadge: weekdayName(result, calendar: calendar),
            payload: .value(display: text, copyText: text))
    }

    /// `5 weekdays from now`, `3 days from today`, `2 weeks ago` — the duration leads.
    private static func parseOffset(
        _ query: String, echo: String, now: Date, calendar: Calendar
    ) -> CalcResult? {
        let durationText: String
        let anchorText: String
        let sign: Int
        let connectors = [(" from ", 1), (" after ", 1), (" before ", -1)]
        if let (range, direction) = connectors.lazy.compactMap({ connector, direction in
            query.range(of: connector).map { ($0, direction) }
        }).first {
            durationText = String(query[..<range.lowerBound])
            anchorText = String(query[range.upperBound...])
            sign = direction
        } else if query.hasSuffix(" ago") {
            durationText = String(query.dropLast(4))
            anchorText = ""
            sign = -1
        } else {
            return nil
        }

        guard let durations = parseDurations(durationText) else { return nil }
        let subDay = durations.contains(where: \.subDay)
        let anchorPhrase = anchorText.isEmpty ? (subDay ? "now" : "today") : anchorText
        guard let anchor = parseMoment(anchorPhrase, now: now, calendar: calendar),
            let shifted = shift(anchor, by: durationText, op: sign < 0 ? "-" : "+", calendar: calendar)
        else { return nil }
        let result = shifted.date
        let hasTime = shifted.hasTime && (subDay || anchorPhrase != "now")
        let display = answerString(result, hasTime: hasTime, now: now, calendar: calendar)
        return CalcResult(
            expression: echo,
            sourceBadge: momentString(
                anchor.date, hasTime: hasTime, now: now, calendar: calendar),
            targetBadge: weekdayName(result, calendar: calendar),
            payload: .value(
                display: display, copyText: display))
    }

    private static func parseUntil(
        _ query: String, echo: String, now: Date, calendar: Calendar
    ) -> CalcResult? {
        guard let connector = [" until ", " till ", " til "].first(where: query.contains) else { return nil }
        return parseInterval(
            query, connector: connector, past: false, echo: echo, now: now, calendar: calendar)
    }

    private static func parseSince(
        _ query: String, echo: String, now: Date, calendar: Calendar
    ) -> CalcResult? {
        parseInterval(query, connector: " since ", past: true, echo: echo, now: now, calendar: calendar)
    }

    private static func parseInterval(
        _ query: String, connector: String, past: Bool, echo: String, now: Date, calendar: Calendar
    ) -> CalcResult? {
        let parts = query.components(separatedBy: connector)
        let bias: MomentBias = past ? .past : .future
        guard parts.count == 2, let unit = durationUnit(parts[0]),
            let moment = parseMoment(parts[1], now: now, calendar: calendar, bias: bias)
                ?? dayAndMonth(parts[1], now: now, calendar: calendar, bias: bias)
        else { return nil }
        let start = past ? moment.date : now
        let end = past ? now : moment.date
        let value = measure(from: start, to: end, in: unit, calendar: calendar)
        let word = abs(value) == 1 ? unit.singular : unit.plural
        return CalcResult(
            expression: echo,
            sourceBadge: unit.subDay
                ? timeString(start, calendar: calendar) : dateString(start, now: now, calendar: calendar),
            targetBadge: unit.subDay
                ? timeString(end, calendar: calendar) : dateString(end, now: now, calendar: calendar),
            payload: .number(value, suffix: " \(word)"))
    }

    /// `29.10` and `29/10` after `until`: no decimal follows that word, so a lone pair is a date.
    private static func dayAndMonth(
        _ phrase: String, now: Date, calendar: Calendar, bias: MomentBias
    ) -> Moment? {
        let text = phrase.hasSuffix(".") ? String(phrase.dropLast()) : phrase
        let parts = text.split(separator: text.contains("/") ? "/" : ".", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ (1...2).contains($0.count) }),
            let day = Int(parts[0]), let month = Int(parts[1])
        else { return nil }
        return monthDayMoment(month: month, day: day, now: now, calendar: calendar, bias: bias)
    }

    // MARK: - Grammars C & D: moment ± duration / moment − moment

    private static func parseArithmetic(
        _ query: String, echo: String, now: Date, calendar: Calendar
    ) -> CalcResult? {
        var expression = query
        var targetUnit: UnitDef?
        for connector in [" to ", " in "] {
            if let range = expression.range(of: connector, options: .backwards),
                let unit = CalcUnits.byName[String(expression[range.upperBound...])], unit.category == .time
            {
                targetUnit = unit
                expression = String(expression[..<range.lowerBound])
                break
            }
        }
        let (left, operation, tail) = splitTerm(expression[...])
        guard let op = operation else { return nil }
        let right = String(tail)
        let firstTerm = splitTerm(tail).term
        let shifts = parseDurations(firstTerm) != nil || Double(firstTerm) != nil
        guard var base = parseMoment(left, now: now, calendar: calendar, bias: shifts ? .nearest : .future)
        else { return nil }
        if !shifts, base.hasTime {
            guard let local = parseMoment(left, now: now, calendar: calendar, bias: .nearest) else {
                return nil
            }
            base = local
        }

        // C: moment ± duration, chained left to right — every term after the first shifts again.
        if targetUnit == nil, let shifted = applyShifts(op, right, to: base, calendar: calendar) {
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
            targetUnit != nil || base.hasTime || left.contains(where: \.isLetter)
                || right.contains(where: \.isLetter) || left.contains("-") || isDottedDate(atomize(left)),
            let other = parseMoment(
                right, now: now, calendar: calendar, bias: base.hasTime ? .nearest : .future)
        else {
            return nil
        }
        let payload: CalcResult.Payload =
            if let unit = targetUnit {
                .measurement(base.date.timeIntervalSince(other.date) / unit.factor, unit: unit)
            } else {
                difference(from: other, to: base, calendar: calendar)
            }
        return CalcResult(
            expression: echo,
            sourceBadge: momentString(base.date, hasTime: base.hasTime, now: now, calendar: calendar),
            targetBadge: targetUnit?.name
                ?? momentString(other.date, hasTime: other.hasTime, now: now, calendar: calendar),
            payload: payload)
    }

    // MARK: - Grammar H: the span between two moments

    private enum SpanUnit {
        case duration(DurUnit)
        case workdays
    }

    private static func parseSpan(
        _ query: String, echo: String, now: Date, calendar: Calendar
    ) -> CalcResult? {
        var phrase = query
        let midpoint = phrase.hasPrefix("halfway ") || phrase.hasPrefix("midpoint ")
        if midpoint, let space = phrase.firstIndex(of: " ") {
            phrase = String(phrase[phrase.index(after: space)...])
        }
        let whole = !midpoint && phrase.hasPrefix("whole ")
        if whole { phrase.removeFirst(6) }
        var unit: SpanUnit?
        if let range = phrase.range(of: " in ", options: .backwards),
            let named = spanUnit(String(phrase[range.upperBound...]))
        {
            unit = named
            phrase = String(phrase[..<range.lowerBound])
        }
        var led = false
        if unit == nil, let space = phrase.firstIndex(of: " "), let named = spanUnit(String(phrase[..<space]))
        {
            unit = named
            led = true
            phrase = String(phrase[phrase.index(after: space)...])
        }
        guard let ends = spanEnds(phrase, led: led),
            let start = parseMoment(ends.start, now: now, calendar: calendar, bias: .nearest),
            let end = parseMoment(ends.end, now: now, calendar: calendar, bias: .nearest),
            unit != nil || start.hasTime || end.hasTime || (ends.start + ends.end).contains(where: \.isLetter)
                || (ends.start + ends.end).contains("-") || isDottedDate(atomize(ends.start))
        else { return nil }

        var span = (start: start, end: end)
        if isBareClock(ends.start), isBareClock(ends.end) {
            guard let opening = clockToday(start.date, now: now, calendar: calendar),
                var closing = clockToday(end.date, now: now, calendar: calendar)
            else { return nil }
            if closing <= opening, let tomorrow = shift(closing, days: 1, calendar: calendar) {
                closing = tomorrow
            }
            span = (Moment(date: opening, hasTime: true), Moment(date: closing, hasTime: true))
        }
        let badges = (
            momentString(span.start.date, hasTime: span.start.hasTime, now: now, calendar: calendar),
            momentString(span.end.date, hasTime: span.end.hasTime, now: now, calendar: calendar)
        )
        if midpoint {
            guard unit == nil, !ends.inclusive else { return nil }
            return halfway(from: span.start, to: span.end, echo: echo, now: now, calendar: calendar)
        }
        if ends.inclusive, !start.hasTime, !end.hasTime {
            guard let next = shift(end.date, days: 1, calendar: calendar) else { return nil }
            span.end = Moment(date: next, hasTime: false)
        }
        guard !whole || unit != nil else { return nil }
        return spanResult(
            from: span.start, to: span.end, unit: unit, whole: whole, echo: echo, badges: badges,
            calendar: calendar)
    }

    /// The moment halfway along a span; between two days, the day nearest the middle.
    private static func halfway(
        from start: Moment, to end: Moment, echo: String, now: Date, calendar: Calendar
    ) -> CalcResult? {
        let hasTime = start.hasTime || end.hasTime
        let middle: Date?
        if hasTime {
            middle = start.date.addingTimeInterval(end.date.timeIntervalSince(start.date) / 2)
        } else {
            let days = calendar.dateComponents([.day], from: start.date, to: end.date).day ?? 0
            middle = shift(start.date, days: Int((Double(days) / 2).rounded()), calendar: calendar)
        }
        guard let middle else { return nil }
        let text = answerString(middle, hasTime: hasTime, now: now, calendar: calendar)
        return CalcResult(
            expression: echo, sourceBadge: String(localized: "Midpoint"),
            targetBadge: weekdayName(middle, calendar: calendar),
            payload: .value(display: text, copyText: text))
    }

    private static func spanResult(
        from start: Moment, to end: Moment, unit: SpanUnit?, whole: Bool, echo: String,
        badges: (String, String),
        calendar: Calendar
    ) -> CalcResult? {
        let payload: CalcResult.Payload
        switch unit {
        case nil:
            payload = difference(from: start, to: end, calendar: calendar)
        case .workdays:
            guard let count = businessDays(from: start.date, to: end.date, calendar: calendar) else {
                return nil
            }
            payload = .number(Double(count), suffix: abs(count) == 1 ? " workday" : " workdays")
        case .duration(let unit):
            let measured = measure(from: start.date, to: end.date, in: unit, calendar: calendar)
            let value = whole ? measured.rounded(.towardZero) : measured
            payload = .number(value, suffix: " \(abs(value) == 1 ? unit.singular : unit.plural)")
        }
        return CalcResult(expression: echo, sourceBadge: badges.0, targetBadge: badges.1, payload: payload)
    }

    private static func spanUnit(_ name: String) -> SpanUnit? {
        if businessDayPhrases.contains(name.replacingOccurrences(of: " ", with: "")) { return .workdays }
        guard !name.contains(" ") else { return nil }
        return durationUnit(name).map(SpanUnit.duration)
    }

    /// A leading unit needs `between` or `from`, so `days march 5` is not read as a span.
    private static func spanEnds(
        _ phrase: String, led: Bool
    ) -> (start: String, end: String, inclusive: Bool)? {
        func split(_ text: some StringProtocol, on separator: String) -> (String, String)? {
            let parts = text.components(separatedBy: separator)
            return parts.count == 2 ? (parts[0], parts[1]) : nil
        }
        if phrase.hasPrefix("between "), let (start, end) = split(phrase.dropFirst(8), on: " and ") {
            return (start, end, false)
        }
        if phrase.hasPrefix("from ") {
            if let (start, end) = split(phrase.dropFirst(5), on: " to ") { return (start, end, false) }
            if let (start, end) = split(phrase.dropFirst(5), on: " through ") { return (start, end, true) }
        }
        guard !led else { return nil }
        if let (start, end) = split(phrase, on: " through ") { return (start, end, true) }
        return split(phrase, on: " to ").map { ($0.0, $0.1, false) }
    }

    private static func isBareClock(_ phrase: String) -> Bool {
        let atoms = atomize(phrase)
        switch atoms.count {
        case 1:
            return atoms[0] == "noon" || atoms[0] == "midnight"
                || (atoms[0].contains(":") && parseClock(atoms[0]) != nil)
        case 2:
            return (atoms[1] == "am" || atoms[1] == "pm") && parseClock(atoms[0]) != nil
        default:
            return false
        }
    }

    /// A bare clock read on today, so `4pm to 3am` runs forward into tomorrow whatever the bias picked.
    private static func clockToday(_ date: Date, now: Date, calendar: Calendar) -> Date? {
        let clock = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = clock.hour, let minute = clock.minute else { return nil }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now)
    }

    /// A clock on either side measures elapsed time; two dates count calendar days.
    private static func difference(
        from start: Moment, to end: Moment, calendar: Calendar
    ) -> CalcResult.Payload {
        if start.hasTime || end.hasTime {
            let text = CalcFormatter.timespan(end.date.timeIntervalSince(start.date))
            return .value(display: text, copyText: text)
        }
        let days =
            calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: start.date), to: calendar.startOfDay(for: end.date)
            ).day ?? 0
        let text = "\(days) \(abs(days) == 1 ? "day" : "days")"
        return .value(display: text, copyText: text)
    }

    /// Whole calendar days for day and week units, elapsed time for anything shorter.
    private static func measure(
        from start: Date, to end: Date, in unit: DurUnit, calendar: Calendar
    ) -> Double {
        guard !unit.subDay else { return end.timeIntervalSince(start) / unit.seconds }
        let days =
            calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)
            ).day ?? 0
        return Double(days) / (unit.kind == .week ? 7 : 1)
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
        let phrase = Double(trimmed) == nil ? trimmed : "\(trimmed) \(moment.hasTime ? "hours" : "days")"
        guard let durations = parseDurations(phrase) else { return nil }
        var result = moment
        for duration in durations {
            let signed = op == "-" ? -duration.count : duration.count
            let date =
                duration.businessDays
                ? addBusinessDays(signed, to: result.date, calendar: calendar)
                : calendar.date(byAdding: duration.component, value: signed, to: result.date)
            guard let date, (1...9999).contains(calendar.component(.year, from: date)) else { return nil }
            result = Moment(date: date, hasTime: result.hasTime || duration.subDay)
        }
        return result
    }

    private static func shiftedMoment(_ source: String, now: Date, calendar: Calendar) -> Moment? {
        let (term, op, tail) = splitTerm(source[...])
        guard let moment = parseMoment(term, now: now, calendar: calendar, bias: .nearest) else { return nil }
        guard let op else { return moment }
        return applyShifts(op, String(tail), to: moment, calendar: calendar)
    }

    // MARK: - Moment parsing

    private struct Moment {
        let date: Date
        /// True when the phrase named a clock time ("9am", "now") — drives the time badge.
        let hasTime: Bool
    }

    private static func parseTimestamp(
        _ phrase: String, echo: String, now: Date, calendar: Calendar
    ) -> CalcResult? {
        let current: Set<String> = ["current timestamp", "current unix timestamp", "new timestamp"]
        let query = current.contains(phrase) ? "now to unix" : phrase
        if let range = query.range(of: " to ", options: .backwards),
            ["iso", "iso8601"].contains(query[range.upperBound...])
        {
            guard let moment = shiftedMoment(String(query[..<range.lowerBound]), now: now, calendar: calendar)
            else { return nil }
            let text = CalcDateFormatters.string(
                from: moment.date, calendar: calendar, zone: calendar.timeZone,
                pattern: "yyyy-MM-dd'T'HH:mm:ssxxx")
            return CalcResult(
                expression: echo, sourceBadge: String(localized: "Date"), targetBadge: "ISO 8601",
                payload: .value(display: text, copyText: text))
        }
        if let range = query.range(of: " to ", options: .backwards),
            let scale = CalcTimestamp.scale(String(query[range.upperBound...]))
        {
            guard let moment = shiftedMoment(String(query[..<range.lowerBound]), now: now, calendar: calendar)
            else { return nil }
            let timestamp = moment.date.timeIntervalSince1970 * scale
            let rounded = timestamp.rounded()
            let tolerance = moment.date.timeIntervalSinceReferenceDate.ulp * scale
            let whole = abs(timestamp - rounded) <= tolerance ? rounded : timestamp.rounded(.down)
            guard let value = Int64(exactly: whole)
            else { return nil }
            let text = String(value)
            return CalcResult(
                expression: echo, sourceBadge: String(localized: "Date"),
                targetBadge: scale == 1
                    ? String(localized: "Unix Seconds") : String(localized: "Unix Milliseconds"),
                payload: .value(display: CalcFormatter.grouped(text), copyText: text))
        }
        var source = query.hasSuffix(" to date") ? String(query.dropLast(8)) : query
        if source != query, let seconds = Double(source) {
            // Past year 5138 in seconds, so a thirteen-digit stamp is milliseconds.
            source = abs(seconds) >= 1e11 ? "unix \(source) ms" : "unix \(source)"
        }
        guard CalcTimestamp.isoDate(source) != nil || CalcTimestamp.epochDate(source) != nil else {
            return nil
        }
        return bareMoment(source, echo: echo, now: now, calendar: calendar)
    }

    /// `easter 2027`: a holiday read in the year written, which needs no other qualifier.
    private static func holidayYear(_ phrase: String) -> (name: String, year: Int)? {
        guard let space = phrase.lastIndex(of: " ") else { return nil }
        let name = String(phrase[..<space])
        guard let year = Int(phrase[phrase.index(after: space)...]), (1000...9999).contains(year),
            CalcHolidays.isHoliday(name)
        else { return nil }
        return (name, year)
    }

    private static func holidayMoment(
        _ name: String, now: Date, calendar: Calendar, bias: MomentBias
    ) -> Moment? {
        let year = calendar.component(.year, from: now)
        guard let thisYear = CalcHolidays.date(name, year: year, calendar: calendar) else { return nil }
        let sod = calendar.startOfDay(for: now)
        let date: Date?
        switch bias {
        case .future:
            date = thisYear >= sod ? thisYear : CalcHolidays.date(name, year: year + 1, calendar: calendar)
        case .past:
            date = thisYear <= sod ? thisYear : CalcHolidays.date(name, year: year - 1, calendar: calendar)
        case .nearest: date = thisYear
        }
        return date.map { Moment(date: $0, hasTime: false) }
    }

    private static func withoutApostrophes(_ phrase: String) -> String {
        phrase.unicodeScalars.contains { $0 == "'" || $0 == "’" }
            ? phrase.replacingOccurrences(of: "['’]", with: "", options: .regularExpression) : phrase
    }

    /// The day a phrase names, nearest occurrence first, for a caller that only wants the date.
    static func day(_ phrase: String, now: Date, calendar: Calendar) -> Date? {
        parseMoment(phrase, now: now, calendar: calendar, bias: .nearest)?.date
    }

    /// A day and a clock read on `calendar`'s own zone, for a caller that converts the instant.
    static func wallMoment(_ phrase: String, now: Date, calendar: Calendar) -> Date? {
        guard let moment = parseMoment(phrase, now: now, calendar: calendar, bias: .nearest),
            moment.hasTime
        else { return nil }
        return moment.date
    }

    private static func parseMoment(
        _ phrase: String, now: Date, calendar: Calendar, bias: MomentBias = .future
    ) -> Moment? {
        if let date = CalcTimestamp.isoDate(phrase) ?? CalcTimestamp.epochDate(phrase) {
            return Moment(date: date, hasTime: true)
        }
        if let edge = boundary(phrase) {
            return boundaryDate(edge, now: now, calendar: calendar).map { Moment(date: $0, hasTime: false) }
        }
        let name = withoutApostrophes(phrase)
        if CalcHolidays.isHoliday(name) {
            return holidayMoment(name, now: now, calendar: calendar, bias: bias)
        }
        if let (holiday, year) = holidayYear(name) {
            return CalcHolidays.date(holiday, year: year, calendar: calendar).map {
                Moment(date: $0, hasTime: false)
            }
        }
        if let range = phrase.range(of: " at ") {
            let dayPhrase = String(phrase[..<range.lowerBound])
            let atoms = atomize(dayPhrase)
            let recurring =
                weekdayByName[dayPhrase] != nil || monthByName[dayPhrase] != nil
                || CalcHolidays.isHoliday(withoutApostrophes(dayPhrase))
                || (atoms.count == 2 && namesADay(dayPhrase))
                || (atoms.count == 1 && dayPhrase.split(separator: "/").count == 2)
            guard let clock = parseMeridiemClock(String(phrase[range.upperBound...])),
                let day = parseMoment(
                    dayPhrase, now: now, calendar: calendar,
                    bias: recurring && bias != .nearest ? .future : bias)
            else { return nil }
            var anchor = day.date
            if recurring, bias != .nearest,
                let candidate = calendar.date(
                    bySettingHour: clock.hour, minute: clock.minute, second: 0, of: anchor),
                bias == .future ? candidate <= now : candidate > now
            {
                guard let reference = shift(now, days: bias == .future ? 1 : -1, calendar: calendar),
                    let shifted = parseMoment(dayPhrase, now: reference, calendar: calendar, bias: bias)
                else { return nil }
                anchor = shifted.date
            }
            guard
                let date = calendar.date(
                    bySettingHour: clock.hour, minute: clock.minute, second: 0, of: anchor),
                calendar.isDate(date, inSameDayAs: anchor),
                calendar.component(.hour, from: date) == clock.hour,
                calendar.component(.minute, from: date) == clock.minute
            else { return nil }
            return Moment(date: date, hasTime: true)
        }
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
        if let month = monthByName[b], let day = ordinalDay(a) {
            return monthDayMoment(month: month, day: day, now: now, calendar: calendar, bias: bias)
        }
        if let month = monthByName[a], let day = ordinalDay(b) {
            return monthDayMoment(month: month, day: day, now: now, calendar: calendar, bias: bias)
        }
        if b == "am" || b == "pm", let (hour, minute) = parseClock(a) {
            guard (1...12).contains(hour) else { return nil }
            let adjusted = b == "pm" ? (hour % 12) + 12 : hour % 12
            return clockMoment(
                hour: adjusted, minute: minute, now: now, calendar: calendar, bias: bias)
        }
        if a == "this" {
            if let weekday = weekdayByName[b] {
                return nextWeekday(weekday, offsetToFuture: false, now: now, calendar: calendar)
            }
            return monthByName[b].flatMap {
                monthDayMoment(month: $0, day: 1, now: now, calendar: calendar, bias: .nearest)
            }
        }
        if a == "next" || a == "last" {
            if let period = ["week": Calendar.Component.weekOfYear, "month": .month, "year": .year][b] {
                return calendar.date(
                    byAdding: period, value: a == "next" ? 1 : -1, to: calendar.startOfDay(for: now)
                ).map { Moment(date: $0, hasTime: false) }
            }
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
        let separator: Character = atom.contains("-") ? "-" : atom.contains("/") ? "/" : "."
        let parts = atom.split(separator: separator)
        guard (2...3).contains(parts.count), let first = Int(parts[0]), let second = Int(parts[1]) else {
            return nil
        }
        if separator == "/", parts.count == 2 {
            return monthDayMoment(month: first, day: second, now: now, calendar: calendar, bias: bias)
        }
        guard parts.count == 3, let third = Int(parts[2]) else { return nil }
        let year: Int
        let month: Int
        let day: Int
        switch separator {
        case "-":
            guard first > 31 else { return nil }
            (year, month, day) = (first, second, third)
        case "/":
            (year, month, day) = (fullYear(third), first, second)
        default:
            guard parts[2].count == 2 || parts[2].count == 4 else { return nil }
            (year, month, day) = (fullYear(third), second, first)
        }
        guard let date = makeDate(year, month, day, calendar) else { return nil }
        return Moment(date: date, hasTime: false)
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

    private static func parseDurations(_ phrase: String) -> [DurationPhrase]? {
        let atoms = atomize(phrase)
        var durations: [DurationPhrase] = []
        var index = 0
        while index + 1 < atoms.count {
            guard let amount = Double(atoms[index]), amount.isFinite else { return nil }
            var name = atoms[index + 1]
            index += 2
            if index < atoms.count, businessDayPhrases.contains(name + atoms[index]) {
                name += atoms[index]
                index += 1
            }
            let component: Calendar.Component
            let count: Double
            let subDay: Bool
            let businessDays = businessDayPhrases.contains(name)
            if businessDays {
                component = .day
                count = amount
                subDay = false
            } else if ["mo", "month", "months", "yr", "year", "years"].contains(name) {
                component = name.hasPrefix("mo") ? .month : .year
                count = amount
                subDay = false
            } else if let unit = durationUnit(name) {
                component = unit.subDay ? .second : .day
                count = amount * (unit.subDay ? unit.seconds : unit.seconds / 86400)
                subDay = unit.subDay
                guard subDay || amount.rounded() == amount else { return nil }
            } else {
                return nil
            }
            guard let value = Int(exactly: count), value != .min else { return nil }
            durations.append(
                DurationPhrase(count: value, component: component, subDay: subDay, businessDays: businessDays)
            )
        }
        return index == atoms.count && !durations.isEmpty ? durations : nil
    }

    // MARK: - Formatting

    private static func momentString(
        _ date: Date, hasTime: Bool, now: Date, calendar: Calendar
    )
        -> String
    {
        let day = dateString(date, now: now, calendar: calendar)
        return hasTime ? String(localized: "\(day) at \(timeString(date, calendar: calendar))") : day
    }

    /// The weekday moves to the badge, so an answered moment leads with the date itself.
    private static func answerString(
        _ date: Date, hasTime: Bool, now: Date, calendar: Calendar
    ) -> String {
        let sameYear =
            calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let day = format(
            date, calendar: calendar, pattern: sameYear ? "d MMMM" : "d MMMM, yyyy")
        return hasTime ? String(localized: "\(day) at \(timeString(date, calendar: calendar))") : day
    }

    private static func dateString(_ date: Date, now: Date, calendar: Calendar) -> String {
        let sameYear =
            calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return format(
            date, calendar: calendar, pattern: sameYear ? "EEEE, d MMMM" : "EEEE, d MMMM, yyyy")
    }

    private static func timeString(_ date: Date, calendar: Calendar) -> String {
        let template = calendar.component(.second, from: date) == 0 ? "jmm" : "jmmss"
        return CalcDateFormatters.string(
            from: date, calendar: calendar, zone: calendar.timeZone, template: template)
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
        return foldOrdinals(atoms)
    }

    private static let ordinalSuffixes: Set<String> = ["st", "nd", "rd", "th"]

    /// `the 29th of october` reads as `29 october`: the suffix, the `the` and the `of` say nothing.
    private static func foldOrdinals(_ atoms: [String]) -> [String] {
        var folded: [String] = []
        folded.reserveCapacity(atoms.count)
        for (index, atom) in atoms.enumerated() {
            let next = index + 1 < atoms.count ? atoms[index + 1] : nil
            let afterDay = folded.last.map { $0.allSatisfy(\.isNumber) } ?? false
            if afterDay, ordinalSuffixes.contains(atom) { continue }
            if afterDay, atom == "of", let next, monthByName[next] != nil { continue }
            if atom == "the", let next, next.first?.isNumber == true { continue }
            folded.append(atom)
        }
        return folded
    }

    /// A day number, with the ordinal dot German and Austrian dates write: `28. aug`.
    private static func ordinalDay(_ atom: String) -> Int? {
        Int(atom.hasSuffix(".") ? String(atom.dropLast()) : atom)
    }

    private static func parseClock(_ atom: String) -> (hour: Int, minute: Int)? {
        if atom.contains(":") {
            let parts = atom.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
                (0...59).contains(minute)
            else {
                return nil
            }
            return (hour, minute)
        }
        guard let hour = Int(atom) else { return nil }
        return (hour, 0)
    }

    @inline(never) private static func makeDate(
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

    /// Whole weeks jump at once; only the weekend alignment and remainder walk individual days.
    private static func addBusinessDays(_ count: Int, to date: Date, calendar: Calendar) -> Date? {
        guard (-10_000...10_000).contains(count) else { return nil }
        let step = count < 0 ? -1 : 1
        var remaining = abs(count)
        var cursor = date
        while remaining > 0, isWeekend(cursor, calendar: calendar) {
            guard let next = shift(cursor, days: step, calendar: calendar) else { return nil }
            cursor = next
            if !isWeekend(cursor, calendar: calendar) { remaining -= 1 }
        }
        guard let jumped = shift(cursor, days: remaining / 5 * 7 * step, calendar: calendar) else {
            return nil
        }
        cursor = jumped
        remaining %= 5
        while remaining > 0 {
            guard let next = shift(cursor, days: step, calendar: calendar) else { return nil }
            cursor = next
            if !isWeekend(cursor, calendar: calendar) { remaining -= 1 }
        }
        return cursor
    }

    /// Weekdays from `start` up to `end`, jumping whole weeks so a long span stays cheap.
    /// Weekdays from `start` up to `end`, whole weeks jumped so a long span stays cheap.
    static func businessDays(from start: Date, to end: Date, calendar: Calendar) -> Int? {
        let first = calendar.startOfDay(for: min(start, end))
        guard
            let length = calendar.dateComponents(
                [.day], from: first, to: calendar.startOfDay(for: max(start, end))
            ).day,
            length <= 10_000, var cursor = shift(first, days: length / 7 * 7, calendar: calendar)
        else { return nil }
        var count = length / 7 * 5
        for _ in 0..<(length % 7) {
            if !isWeekend(cursor, calendar: calendar) { count += 1 }
            guard let next = shift(cursor, days: 1, calendar: calendar) else { return nil }
            cursor = next
        }
        return start <= end ? count : -count
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

    private static let weekdayByName: [String: Int] = [
        "sunday": 1, "sun": 1, "monday": 2, "mon": 2, "tuesday": 3, "tue": 3, "tues": 3,
        "wednesday": 4, "wed": 4, "thursday": 5, "thu": 5, "thurs": 5, "friday": 6, "fri": 6,
        "saturday": 7, "sat": 7
    ]
}
