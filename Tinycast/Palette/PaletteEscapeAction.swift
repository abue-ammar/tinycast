import Foundation

/// Ordered like a bare backspace: a screen is only left once the search field is empty.
enum PaletteEscapeAction: Equatable {
    case clearMenuQuery
    case closeMenu
    case leaveArgumentField
    case clearQuery
    case goBack
    case collapsePalette
    case hidePalette

    static func resolve(
        menuOpen: Bool, menuQuery: String, argumentFocused: Bool, query: String, canGoBack: Bool,
        behavior: EscapeKeyBehavior, compactRootExpanded: Bool = false
    ) -> Self {
        if menuOpen { return menu(query: menuQuery) }
        // An argument field is a step deeper than the query, so it is left before anything clears.
        if argumentFocused { return .leaveArgumentField }
        if !query.isEmpty { return .clearQuery }
        if compactRootExpanded { return .collapsePalette }
        guard behavior == .navigateBackOrClose else { return .hidePalette }
        return canGoBack ? .goBack : .hidePalette
    }

    static func menu(query: String) -> Self {
        query.isEmpty ? .closeMenu : .clearMenuQuery
    }
}
