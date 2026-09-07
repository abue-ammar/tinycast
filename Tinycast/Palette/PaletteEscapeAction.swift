import Foundation

/// Ordered like a bare backspace: a screen is only left once the search field is empty.
enum PaletteEscapeAction: Equatable {
    case closeMenu
    case leaveArgumentField
    case clearQuery
    case exitExtensionScreen
    case exitToLauncher
    case hidePalette

    static func resolve(
        menuOpen: Bool, argumentFocused: Bool, query: String, mode: PaletteMode
    ) -> Self {
        if menuOpen { return .closeMenu }
        // An argument field is a step deeper than the query, so it is left before anything clears.
        if argumentFocused { return .leaveArgumentField }
        if !query.isEmpty { return .clearQuery }
        // An extension pops its own navigation stack before the command is left.
        if mode == .extensionCommand { return .exitExtensionScreen }
        // Chat is a surface of its own, so leaving it lands on the launcher, not on nothing.
        if mode == .ai { return .exitToLauncher }
        return .hidePalette
    }
}
