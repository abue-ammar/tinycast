import Foundation

/// What the Mac will let Tinycast's Reminders extension read and write.
enum RemindersAccess: Sendable {
    case notDetermined
    case granted
    /// Denied or restricted: only System Settings can undo it, so both read the same to us.
    case denied
}
