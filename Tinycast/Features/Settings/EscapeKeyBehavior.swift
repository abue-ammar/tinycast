import Foundation

/// Whether Escape walks back a screen at a time, or closes the launcher and resets it in one press.
enum EscapeKeyBehavior: String, CaseIterable, Identifiable, Sendable {
    case navigateBackOrClose
    case closeAndPopToRoot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .navigateBackOrClose: return String(localized: "Navigate back or close window")
        case .closeAndPopToRoot: return String(localized: "Close window and pop to root")
        }
    }
}
