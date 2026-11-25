import Foundation

/// What the palette holds at the moment Escape is pressed; the shipped defaults are a bare root.
struct PaletteEscapePress {
    var mode: PaletteMode = .launcher
    var query = ""
    /// The open menu's own search text; nil while no menu is open.
    var menuQuery: String?
    var isArgumentFocused = false
    var isAnswering = false
    var canGoBack = false
    var isHotkeyRoot = false
    var extensionCanGoBack = false
    var behavior: EscapeKeyBehavior = .navigateBackOrClose
}

/// One Escape press: the first rung that applies is the only one taken.
enum PaletteEscapeAction: Equatable {
    case clearMenuQuery
    case closeMenu
    case leaveArgumentField
    case stopAnswer
    case clearQuery
    case goBack
    case close
    case closeAndPopToRoot

    static func resolve(_ press: PaletteEscapePress) -> Self {
        if let menuQuery = press.menuQuery { return menuQuery.isEmpty ? .closeMenu : .clearMenuQuery }
        if press.isArgumentFocused { return .leaveArgumentField }
        if press.isAnswering { return .stopAnswer }
        let isRootSearch = press.mode == .launcher
        if press.behavior == .closeAndPopToRoot {
            return isRootSearch && press.query.isEmpty ? .close : .closeAndPopToRoot
        }
        // Quick AI's field holds a message, not a search, so Escape leaves it rather than wiping it.
        if !press.query.isEmpty, press.mode != .ai { return .clearQuery }
        if isRootSearch { return .close }
        if press.extensionCanGoBack { return .goBack }
        return press.isHotkeyRoot ? .closeAndPopToRoot : .goBack
    }
}
