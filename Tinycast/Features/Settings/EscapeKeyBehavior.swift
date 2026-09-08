import Foundation

/// What Escape does on the palette once the search field it would have cleared is already empty.
enum EscapeKeyBehavior: String, CaseIterable, Identifiable, Sendable {
    case navigateBackOrClose
    case closeAndPopToRoot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .navigateBackOrClose: return "Navigate back or close window"
        case .closeAndPopToRoot: return "Close window and pop to root"
        }
    }
}
