// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import Foundation

/// How a room arranges its windows on the display it lands on. `allCases` is Tab's order.
enum RoomLayoutKind: String, Codable, CaseIterable, Sendable {
    /// Focus, Columns or Grid, whichever gives every window a comfortable size; Stack otherwise.
    case auto
    case focus
    case stack
    case columns
    case grid
    case custom
    case saved

    var title: String {
        switch self {
        case .auto: String(localized: "Auto")
        case .focus: String(localized: "Focus")
        case .stack: String(localized: "Stack")
        case .columns: String(localized: "Columns")
        case .grid: String(localized: "Grid")
        case .custom: String(localized: "Custom")
        case .saved: String(localized: "As Arranged")
        }
    }
}
