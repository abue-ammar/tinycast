import Foundation

/// How a close treats the screen it leaves behind.
enum PaletteClose: Equatable, Sendable {
    /// An action ran: something was opened, pasted or copied.
    case afterAction
    /// Nothing ran: Escape, a click elsewhere, or the shortcut that summoned it.
    case dismissed
    /// Back to root search now, whatever Pop to Root Search says.
    case poppingToRoot
    /// The screen outlives this close, however long the palette stays shut.
    case keepingScreen
}

/// When a closed palette goes back to root search.
enum PopToRootPolicy {
    /// An action is done with its result, so the search that found it goes stale sooner.
    static let afterActionLimit: TimeInterval = 15

    /// Seconds until the reset: zero resets at once, nil keeps the screen until the next close.
    static func delay(after close: PaletteClose, timeout: TimeInterval) -> TimeInterval? {
        switch close {
        case .poppingToRoot: 0
        case .keepingScreen: nil
        case .afterAction: min(timeout, afterActionLimit)
        case .dismissed: timeout
        }
    }
}
