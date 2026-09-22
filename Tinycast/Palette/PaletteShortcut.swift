import Foundation

/// A chord aimed at the selected row. The palette recognises it; the screen decides what it does.
enum PaletteShortcut: Equatable {
    /// ⌘⌫ or ⌘⌦.
    case commandDelete
    /// ⌃X.
    case delete
    /// ⌃⇧X.
    case deleteAll
    /// ⇧⌘C.
    case copyFile
    /// ⌥⌘C.
    case copyName
    /// ⌃⌘C.
    case copyPath
    /// ⇧⌘V.
    case pasteFile
    /// ⌘Y.
    case quickLook
    /// ⇧⌘F.
    case toggleFavorite
    /// ⇧⌘H.
    case hideFromSearch
    /// ⌃⇧Q.
    case quit
    /// ⌘R.
    case restart
    /// ⌘J, Quick AI handing its conversation to the AI Chat window.
    case continueInChat
    /// ⌘., which AppKit binds to `cancelOperation:`, so it arrives as a token instead of a key.
    case pin
    /// ⌘1…⌘0, matched by key code in the panel and handed over as a slot.
    case favoriteSlot(Int)

    /// `matches` compares the pressed key through the active layout, so the letters stay positional.
    static func resolve(
        command: Bool, shift: Bool, option: Bool, control: Bool, isDeleteKey: Bool,
        matches: (Character) -> Bool
    ) -> Self? {
        if isDeleteKey { return command ? .commandDelete : nil }
        if command, matches("c") {
            if shift { return .copyFile }
            if option { return .copyName }
            return control ? .copyPath : nil
        }
        if command, shift, matches("v") { return .pasteFile }
        if command, matches("y") { return .quickLook }
        if control, matches("x") { return shift ? .deleteAll : .delete }
        if command, shift, matches("f") { return .toggleFavorite }
        if command, shift, matches("h") { return .hideFromSearch }
        if control, shift, matches("q") { return .quit }
        if command, matches("r") { return .restart }
        if command, matches("j") { return .continueInChat }
        return nil
    }

    /// The compact bar shows no selection, so a chord aimed at a highlighted row waits for the list.
    var requiresExpanded: Bool {
        switch self {
        case .copyFile, .copyName, .copyPath, .pasteFile, .quickLook, .toggleFavorite,
            .hideFromSearch, .quit, .restart:
            true
        case .commandDelete, .delete, .deleteAll, .pin, .favoriteSlot, .continueInChat:
            false
        }
    }

    var closesMenu: Bool {
        switch self {
        case .delete, .deleteAll, .copyFile, .copyName, .copyPath, .quickLook, .toggleFavorite,
            .hideFromSearch:
            true
        case .commandDelete, .pasteFile, .quit, .restart, .pin, .favoriteSlot, .continueInChat:
            false
        }
    }
}
