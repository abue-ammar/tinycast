import Foundation

/// Ordered like a bare backspace: a screen is only left once the search field is empty.
enum PaletteEscapeAction: Equatable {
    case closeMenu
    case leaveArgumentField
    case clearQuery
    case exitExtensionScreen
    case goBack
    /// Clipboard on the Tab ring has no stack, but it still walks back to the launcher.
    case goToLauncher
    case hidePalette

    static func resolve(
        menuOpen: Bool, argumentFocused: Bool, query: String, mode: PaletteMode,
        canGoBack: Bool, behavior: EscapeKeyBehavior
    ) -> Self {
        if menuOpen { return .closeMenu }
        // An argument field is a step deeper than the query, so it is left before anything clears.
        if argumentFocused { return .leaveArgumentField }
        if !query.isEmpty { return .clearQuery }
        guard behavior == .navigateBackOrClose else { return .hidePalette }
        // An extension pops its own navigation stack before the command is left.
        if mode == .extensionCommand { return .exitExtensionScreen }
        // The header has no back chevron here, so a leftover stack must not walk back.
        if mode == .launcher { return .hidePalette }
        // Tab / hotkey clipboard is a root, but Raycast still lands on the launcher.
        if mode == .clipboard { return canGoBack ? .goBack : .goToLauncher }
        return canGoBack ? .goBack : .hidePalette
    }

    /// The field editor binds Escape to `cancelOperation:` and drops an empty-field press.
    static func shouldClaimFromSendEvent(
        isComposing: Bool, isControlListOpen: Bool, isEditingField: Bool
    ) -> Bool {
        !isComposing && !isControlListOpen && !isEditingField
    }
}
