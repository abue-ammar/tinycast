import Foundation

/// One calendar the user can switch off, flattened out of EventKit for the Settings list.
struct MeetingCalendar: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    /// The owning account, so two "Calendar" entries from different accounts stay tellable apart.
    let accountName: String
}
