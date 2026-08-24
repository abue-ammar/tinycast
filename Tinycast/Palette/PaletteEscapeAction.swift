import Foundation

enum PaletteEscapeAction: Equatable {
    case closeMenu
    case clearQuery
    case exitExtensionScreen
    case hidePalette

    static func resolve(menuOpen: Bool, query: String, mode: PaletteMode) -> Self {
        if menuOpen { return .closeMenu }
        if !query.isEmpty { return .clearQuery }
        if mode == .extensionCommand { return .exitExtensionScreen }
        return .hidePalette
    }
}
