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
    /// Exactly where the windows were when the arrangement was remembered.
    case saved

    var title: String {
        switch self {
        case .auto: "Auto"
        case .focus: "Focus"
        case .stack: "Stack"
        case .columns: "Columns"
        case .grid: "Grid"
        case .custom: "Custom"
        case .saved: "As Arranged"
        }
    }
}
