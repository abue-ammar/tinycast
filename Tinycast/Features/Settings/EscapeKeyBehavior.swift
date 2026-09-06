import Foundation

/// What Escape does on an empty search field. Mirrors Raycast's "Escape Key Behavior"; an unset
/// key reads as `.popBackOrClose`, Raycast's own default.
enum EscapeKeyBehavior: String, CaseIterable, Identifiable, Sendable {
    /// Back one screen; at the root, close.
    case popBackOrClose = "popBackOrClose"
    /// Always close, and reset to root search at once. Backspace and the chevron still go back.
    case closeAndPopToRoot = "closeAndPopToRoot"

    /// Raycast spells the same two options in kebab case; anything else is skipped, never guessed.
    init?(raycastValue: String) {
        switch raycastValue {
        case "pop-back-or-close": self = .popBackOrClose
        case "close-and-pop-to-root": self = .closeAndPopToRoot
        default: return nil
        }
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .popBackOrClose: return "Pop back or close"
        case .closeAndPopToRoot: return "Close and pop to root"
        }
    }
}
