import Foundation

/// The zone phrases that carry a day, a span or several places; see `CalcTimeZone` for the clock forms.
extension CalcTimeZone {
    /// `oct 28 at 1pm et`, `tomorrow 3pm pst in tokyo`, `1pm et tomorrow`: a day and a clock in one zone.
    static func datedMoment(_ query: String, now: Date, calendar: Calendar) -> CalcResult? {
        let (zoneQuery, offset) = splitOffset(query)
        let words = zoneQuery.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 3 else { return nil }
        let (head, target) = splitTarget(words, home: calendar.timeZone)
        let tokens = clockTokens(head)
        guard tokens.count >= 3, tokens.contains(where: { parseClock($0) != nil }) else { return nil }

        return extractZone(tokens, minimumRest: 2) { source, rest in
            guard let phrase = dayAndClock(rest),
                var instant = CalcDateTime.wallMoment(phrase, now: now, calendar: wall(source, calendar))
            else { return nil }
            if let offset {
                guard
                    let shifted = calendar.date(byAdding: offset.component, value: offset.count, to: instant)
                else { return nil }
                instant = shifted
            }
            let answer = momentString(instant, zone: target, now: now, calendar: calendar)
            return CalcResult(
                expression: momentString(instant, zone: source, now: now, calendar: calendar),
                sourceBadge: label(for: source), targetBadge: label(for: target),
                payload: .value(display: answer, copyText: answer))
        }
    }

    /// `9am-5pm et in cet`, `9am to 5pm london in tokyo`: a span, with the day as spoken or today.
    static func clockRange(_ query: String, now: Date, calendar: Calendar) -> CalcResult? {
        let words = query.split(whereSeparator: \.isWhitespace).flatMap(splitHyphen)
        guard words.count >= 3 else { return nil }
        let (head, target) = splitTarget(words, home: calendar.timeZone)
        var tokens = clockTokens(head)
        guard
            let start = tokens.indices.first(where: { index in
                index + 2 < tokens.count && parseClock(tokens[index]) != nil
                    && ["-", "to", "until"].contains(tokens[index + 1])
                    && parseClock(tokens[index + 2]) != nil
            })
        else { return nil }
        let (first, last) = (tokens[start], tokens[start + 2])
        tokens.removeSubrange(start...(start + 2))

        func span(in source: TimeZone, day: [String]) -> CalcResult? {
            guard source.identifier != target.identifier else { return nil }
            let phrase = day.isEmpty ? "today" : day.joined(separator: " ")
            let zoned = wall(source, calendar)
            guard let begin = CalcDateTime.wallMoment(phrase + " at " + first, now: now, calendar: zoned),
                var end = CalcDateTime.wallMoment(phrase + " at " + last, now: now, calendar: zoned)
            else { return nil }
            if end <= begin {
                guard let next = zoned.date(byAdding: .day, value: 1, to: end),
                    keepsClock(next, last, calendar: zoned)
                else { return nil }
                end = next
            }
            let note = dayOffsetNote(
                SourceMoment(date: begin, zone: source), target: target, calendar: calendar)
            guard let note else { return nil }
            let lead = day.isEmpty ? "" : dayString(begin, zone: target, now: now, calendar: calendar) + ", "
            let answer = lead + spanString(begin, end, zone: target, calendar: calendar)
            return CalcResult(
                expression: (day.isEmpty
                    ? "" : dayString(begin, zone: source, now: now, calendar: calendar) + ", ")
                    + spanString(begin, end, zone: source, calendar: calendar),
                sourceBadge: label(for: source), targetBadge: label(for: target),
                payload: .value(display: answer + (day.isEmpty ? note : ""), copyText: answer))
        }

        return extractZone(tokens, minimumRest: 0, accept: { span(in: $0, day: $1) })
            ?? span(in: calendar.timeZone, day: tokens)
    }

    /// `1pm et in london, tokyo, sydney`: one card, the times in order and the places in the badge.
    static func worldClock(_ query: String, now: Date, calendar: Calendar) -> CalcResult? {
        guard query.count <= 128,
            let connector = [" in ", " to "].compactMap({ query.range(of: $0, options: .backwards) })
                .max(by: { $0.lowerBound < $1.lowerBound })
        else { return nil }
        let head = String(query[..<connector.lowerBound])
        let places = query[connector.upperBound...].replacingOccurrences(of: " and ", with: ",")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard (2...6).contains(places.count) else { return nil }

        var answers: [CalcResult] = []
        for place in places {
            guard !place.isEmpty,
                let answer = evaluate(head + " in " + place, now: now, calendar: calendar),
                case .value = answer.payload
            else { return nil }
            answers.append(answer)
        }
        let labels = answers.map { $0.targetBadge ?? "" }
        var shown: [String] = []
        var copied: [String] = []
        for (label, answer) in zip(labels, answers) {
            guard case .value(let display, let copy) = answer.payload else { return nil }
            shown.append(display)
            copied.append(label + " " + copy)
        }
        return CalcResult(
            expression: answers[0].expression, sourceBadge: answers[0].sourceBadge,
            targetBadge: labels.joined(separator: " · "),
            payload: .value(display: shown.joined(separator: " · "), copyText: copied.joined(separator: ", "))
        )
    }

    // MARK: - Shared

    private static func wall(_ zone: TimeZone, _ calendar: Calendar) -> Calendar {
        var wall = calendar
        wall.timeZone = zone
        return wall
    }

    /// A trailing `in <zone>` / `to <zone>` names the destination; the home zone stands in otherwise.
    private static func splitTarget(_ words: [String], home: TimeZone) -> ([String], TimeZone) {
        guard let connector = words.indices.last(where: { words[$0] == "in" || words[$0] == "to" }),
            connector > 0, let zone = zone(named: Array(words[(connector + 1)...]))
        else { return (words, home) }
        return (Array(words[..<connector]), zone)
    }

    /// `1 pm` becomes `1pm`, and the `at` / `on` that only join a day to a clock are dropped.
    private static func clockTokens(_ words: [String]) -> [String] {
        var tokens: [String] = []
        for word in words where word != "at" && word != "on" {
            if word == "am" || word == "pm", let last = tokens.last, parseClock(last) != nil,
                parseClock(last + word) != nil
            {
                tokens[tokens.count - 1] = last + word
            } else {
                tokens.append(word)
            }
        }
        return tokens
    }

    /// A day added across a DST gap moves the clock, and a span must not end at a time never written.
    private static func keepsClock(_ date: Date, _ clock: String, calendar: Calendar) -> Bool {
        guard let wanted = parseClock(clock) else { return false }
        let actual = calendar.dateComponents([.hour, .minute], from: date)
        return actual.hour == wanted.hour && actual.minute == wanted.minute
    }

    /// `9am-5pm` is three words, but `2026-10-28` stays one.
    private static func splitHyphen(_ word: Substring) -> [String] {
        let parts = word.split(whereSeparator: { $0 == "-" || $0 == "–" })
        guard parts.count == 2, parseClock(String(parts[0])) != nil, parseClock(String(parts[1])) != nil
        else { return [String(word)] }
        return [String(parts[0]), "-", String(parts[1])]
    }

    private static func extractZone(
        _ tokens: [String], minimumRest: Int, accept: (TimeZone, [String]) -> CalcResult?
    ) -> CalcResult? {
        guard tokens.count > minimumRest else { return nil }
        for length in stride(from: min(3, tokens.count - minimumRest), through: 1, by: -1) {
            for start in stride(from: tokens.count - length, through: 0, by: -1) {
                guard let zone = zone(named: Array(tokens[start..<start + length])) else { continue }
                var rest = tokens
                rest.removeSubrange(start..<start + length)
                if let result = accept(zone, rest) { return result }
            }
        }
        return nil
    }

    private static func dayAndClock(_ words: [String]) -> String? {
        let clock: String
        let day: ArraySlice<String>
        if let last = words.last, parseClock(last) != nil {
            (clock, day) = (last, words.dropLast())
        } else if let first = words.first, parseClock(first) != nil {
            (clock, day) = (first, words.dropFirst())
        } else {
            return nil
        }
        guard !day.isEmpty else { return nil }
        return day.joined(separator: " ") + " at " + clock
    }

    private static func dayString(_ date: Date, zone: TimeZone, now: Date, calendar: Calendar) -> String {
        let local = wall(zone, calendar)
        let sameYear = local.component(.year, from: date) == local.component(.year, from: now)
        return CalcDateFormatters.string(
            from: date, calendar: calendar, zone: zone,
            pattern: sameYear ? "EEEE, d MMMM" : "EEEE, d MMMM, yyyy")
    }

    private static func spanString(_ start: Date, _ end: Date, zone: TimeZone, calendar: Calendar) -> String {
        clockString(start, zone: zone, calendar: calendar) + " – "
            + clockString(end, zone: zone, calendar: calendar)
    }

    private static func momentString(_ date: Date, zone: TimeZone, now: Date, calendar: Calendar) -> String {
        let day = dayString(date, zone: zone, now: now, calendar: calendar)
        return String(localized: "\(day) at \(clockString(date, zone: zone, calendar: calendar))")
    }
}
