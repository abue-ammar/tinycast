import Foundation

/// What Escape does on the palette once the search field it would have cleared is already empty.
enum EscapeKeyBehavior: String, CaseIterable, Identifiable, Sendable {
    case navigateBackOrClose
    case closeAndPopToRoot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .navigateBackOrClose: return String(localized: "Navigate back or close window", bundle: .appLanguage)
        case .closeAndPopToRoot: return String(localized: "Close window and pop to root", bundle: .appLanguage)
        }
    }
}
