import Foundation

/// One calendar occurrence, flattened out of EventKit so nothing EventKit-shaped reaches a view.
struct MeetingEvent: Identifiable, Hashable, Sendable {
    /// Unique per occurrence: a recurring series shares one event identifier across every instance.
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let isDeclined: Bool
    let calendarID: String
    let calendarName: String
    /// EventKit's `calendarItemIdentifier` — the only handle Calendar.app's `ical://` URL accepts.
    let calendarItemID: String
    let link: MeetingLink?

    private static let entryPrefix = "meeting:"

    var entryID: String { Self.entryPrefix + id }

    static func id(fromEntryID entryID: String) -> String? {
        guard entryID.hasPrefix(entryPrefix) else { return nil }
        return String(entryID.dropFirst(entryPrefix.count))
    }

    func isInProgress(now: Date) -> Bool { start <= now && now < end }
}
