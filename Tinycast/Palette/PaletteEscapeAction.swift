import Foundation

/// Ordered like a bare backspace: a screen is only left once the search field is empty.
enum PaletteEscapeAction: Equatable {
    case closeMenu
    case leaveArgumentField
    case clearQuery
    case exitExtensionScreen
    case goBack
    case hidePalette

    static func resolve(
        menuOpen: Bool, argumentFocused: Bool, query: String, mode: PaletteMode,
        canGoBack: Bool, behavior: EscapeKeyBehavior
    ) -> Self {
        if menuOpen { return .closeMenu }
        // An argument field is a step deeper than the query, so it is left before anything clears.
        if argumentFocused { return .leaveArgumentField }
        if !query.isEmpty { return .clearQuery }
        switch behavior {
        case .closeAndPopToRoot:
            // Closing outranks even an extension's own sub-views; Backspace still goes back.
            return .hidePalette
        case .popBackOrClose:
            // An extension pops its own navigation stack before the command is left.
            if mode == .extensionCommand { return .exitExtensionScreen }
            return canGoBack ? .goBack : .hidePalette
        }
    }
}
