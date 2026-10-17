import Foundation

/// Which meeting is worth showing, and whether it is time. Every clock read is an injected `now`.
struct UpcomingWindow: Sendable {
    let leadMinutes: Int

    private var lead: TimeInterval { TimeInterval(leadMinutes * 60) }

    /// The one place the rule lives, so card, chord, schedule and launcher cannot drift.
    static func agenda(from events: [MeetingEvent], now: Date) -> [MeetingEvent] {
        events
            .filter { !$0.isAllDay && !$0.isDeclined && $0.end > now }
            .sorted { $0.start < $1.start }
    }

    /// The grace period never outlives the meeting, so a stand-up clears at its end.
    func carded(from events: [MeetingEvent], now: Date) -> MeetingEvent? {
        Self.agenda(from: events, now: now).first {
            $0.link != nil && now >= $0.start - lead && now < min($0.start + lead, $0.end)
        }
    }

    /// Answers the card first, so the chord always joins what is on screen.
    func joinable(from events: [MeetingEvent], now: Date) -> MeetingEvent? {
        if let carded = carded(from: events, now: now) { return carded }
        let linked = Self.agenda(from: events, now: now).filter { $0.link != nil }
        return linked.first { $0.isInProgress(now: now) } ?? linked.first { $0.start > now }
    }

    static func countdown(to start: Date, now: Date, locale: Locale) -> String {
        let delta = start.timeIntervalSince(now)
        if delta > 0 {
            return String(localized: "in \(duration(delta, rounding: .up, locale: locale))", locale: locale)
        }
        return String(localized: "Now", locale: locale)
    }

    struct RowPill: Equatable, Sendable {
        let text: String
        let isImminent: Bool
    }

    /// A row's pill: a countdown until midnight, then the date, so tomorrow never passes for today.
    static func rowPill(
        for event: MeetingEvent, now: Date, calendar: Calendar, locale: Locale
    ) -> RowPill? {
        if event.isInProgress(now: now) {
            return RowPill(text: String(localized: "Now", locale: locale), isImminent: true)
        }
        let delta = event.start.timeIntervalSince(now)
        guard delta > 0 else { return nil }
        let isImminent = delta <= 60 * 60
        guard isImminent || calendar.isDate(event.start, inSameDayAs: now) else {
            return RowPill(text: dayLabel(event.start, calendar: calendar), isImminent: false)
        }
        return RowPill(text: countdown(to: event.start, now: now, locale: locale), isImminent: isImminent)
    }

    static func dayLabel(_ date: Date, calendar: Calendar) -> String {
        date.formatted(calendar.formatStyle.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// The menu bar names the time left once a meeting has been underway for five minutes.
    static func menuBarCountdown(for event: MeetingEvent, now: Date, locale: Locale) -> String {
        if now < event.start { return countdown(to: event.start, now: now, locale: locale) }
        if now < event.start.addingTimeInterval(5 * 60) { return String(localized: "Now", locale: locale) }
        if now < event.end {
            return String(
                localized:
                    "\(duration(event.end.timeIntervalSince(now), rounding: .down, locale: locale)) left",
                locale: locale)
        }
        return String(localized: "Now", locale: locale)
    }

    private static func duration(
        _ interval: TimeInterval, rounding: FloatingPointRoundingRule, locale: Locale
    ) -> String {
        let minutes = max(1, Int((interval / 60).rounded(rounding)))
        guard minutes > 60 else {
            return Duration.seconds(minutes * 60).formatted(
                .units(allowed: [.minutes], width: .abbreviated).locale(locale))
        }
        let hours = max(1, Int((Double(minutes) / 60).rounded()))
        return Duration.seconds(hours * 3600).formatted(
            .units(allowed: [.hours], width: .abbreviated).locale(locale))
    }
}
