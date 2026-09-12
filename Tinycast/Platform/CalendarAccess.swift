import Foundation

/// What the Mac will let Tinycast read of the user's calendar.
enum CalendarAccess: Sendable {
    case notDetermined
    case granted
    /// Denied or restricted: only System Settings can undo it, so both read the same to us.
    case denied
}
