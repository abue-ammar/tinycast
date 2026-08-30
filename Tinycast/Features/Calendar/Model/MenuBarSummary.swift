import Foundation

/// Which event the menu bar carries, and for how long. Every clock read is an injected `now`.
struct MenuBarSummary: Sendable {
    /// Nil means to keep the next event visible for the rest of today.
    let leadMinutes: Int?
    /// Only events Tinycast could actually join; the rest are appointments, not meetings.
    let linkedOnly: Bool
    private let hideCurrentAtStart: Bool
    private let hideAfterMinutes: Int?
    private let calendar: Calendar

    /// Long enough to recognise a meeting, short enough to leave the menu bar usable.
    static let titleCap = 24
    /// A midnight meeting is useful when it is about to start, but should not keep today's menu bar
    /// occupied for hours.
    static let nextDayGrace: TimeInterval = 30 * 60

    init(
        leadMinutes: Int?, hideAfterMinutes: Int? = nil, linkedOnly: Bool,
        hideCurrentAtStart: Bool = false,
        calendar: Calendar = .current
    ) {
        self.leadMinutes = leadMinutes
        self.linkedOnly = linkedOnly
        self.hideCurrentAtStart = hideCurrentAtStart
        self.hideAfterMinutes = hideAfterMinutes
        self.calendar = calendar
    }

    /// The earliest event still inside its window, so one hiding hands the space to the next.
    func event(from events: [MeetingEvent], now: Date) -> MeetingEvent? {
        UpcomingWindow.agenda(from: events, now: now).first {
            (!linkedOnly || $0.link != nil) && isInsideLead(for: $0, now: now)
                && now < hidesAt($0)
        }
    }

    /// The empty label and the all-day menu-bar choice share one definition of "upcoming".
    static func hasUpcomingEvent(
        from events: [MeetingEvent], now: Date, calendar: Calendar = .current
    ) -> Bool {
        UpcomingWindow.agenda(from: events, now: now).contains {
            calendar.isDate($0.start, inSameDayAs: now) || $0.start <= now + nextDayGrace
        }
    }

    /// Word-boundary-blind on purpose: a hard cap is the only thing that bounds the menu bar.
    static func title(_ title: String) -> String {
        guard title.count > titleCap else { return title }
        return title.prefix(titleCap - 1).trimmingCharacters(in: .whitespaces) + "…"
    }

    private func isInsideLead(for event: MeetingEvent, now: Date) -> Bool {
        guard let leadMinutes else {
            return Self.hasUpcomingEvent(from: [event], now: now, calendar: calendar)
        }
        return now >= event.start - TimeInterval(leadMinutes * 60)
    }

    private func hidesAt(_ event: MeetingEvent) -> Date {
        if hideCurrentAtStart { return event.start }
        guard let hideAfterMinutes else { return event.end }
        return min(event.start + TimeInterval(hideAfterMinutes * 60), event.end)
    }
}
