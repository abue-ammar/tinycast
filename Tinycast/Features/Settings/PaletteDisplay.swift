import Foundation

enum PaletteDisplay: String, CaseIterable, Identifiable, Sendable {
    case mouse
    case focusedWindow
    case primary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mouse: "Mouse display"
        case .focusedWindow: "Focused window display"
        case .primary: "Primary display"
        }
    }

    static func stored(rawValue: String?, openOnCursorScreen: Bool?) -> Self? {
        if let rawValue, let display = Self(rawValue: rawValue) { return display }
        return openOnCursorScreen.map { $0 ? .mouse : .primary }
    }
}
