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
    /// ⇧⌘T.
    case copyText
    /// ⇧⌘↵, matched by the Return handler rather than `resolve`.
    case copyCalculation
    /// ⇧⌘V.
    case pasteFile
    /// ⌘Y.
    case quickLook
    /// ⌘O, the row handed to the app that owns it.
    case openInApp
    /// ⌘I.
    case showDetails
    /// ⇧⌘F.
    case toggleFavorite
    /// ⇧⌘H.
    case hideFromSearch
    /// ⌃⇧Q.
    case quit
    /// ⌃⌥⇧Q.
    case forceQuit
    /// ⌘R.
    case restart
    /// ⌘N, a new one of whatever the screen holds.
    case newItem
    /// ⌘E, the row opened in its editor.
    case edit
    /// ⌘D.
    case duplicate
    /// ⌘F, for a screen whose ⌘↵ already does something else.
    case showInFinder
    /// ⌥⌘,, the screen's own settings; ⌘, alone stays the app's.
    case settings
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
        if command, shift, matches("t") { return .copyText }
        if command, matches("y") { return .quickLook }
        if command, !shift, matches("o") { return .openInApp }
        if command, !shift, matches("i") { return .showDetails }
        if control, matches("x") { return shift ? .deleteAll : .delete }
        if command, matches("f") { return shift ? .toggleFavorite : .showInFinder }
        if command, shift, matches("h") { return .hideFromSearch }
        if control, shift, matches("q") { return option ? .forceQuit : .quit }
        if command, matches("r") { return .restart }
        if command, !shift, matches("n") { return .newItem }
        if command, !shift, !option, !control, matches("e") { return .edit }
        if command, !shift, matches("d") { return .duplicate }
        if command, option, matches(",") { return .settings }
        if command, matches("j") { return .continueInChat }
        return nil
    }

    /// The compact bar shows no selection, so a chord aimed at a highlighted row waits for the list.
    var requiresExpanded: Bool {
        switch self {
        case .copyFile, .copyName, .copyPath, .copyText, .pasteFile, .quickLook, .openInApp,
            .showDetails, .toggleFavorite, .hideFromSearch, .quit, .forceQuit, .restart, .edit,
            .duplicate, .showInFinder:
            true
        case .commandDelete, .delete, .deleteAll, .pin, .favoriteSlot, .continueInChat, .newItem,
            .settings, .copyCalculation:
            false
        }
    }

    var closesMenu: Bool {
        switch self {
        case .delete, .deleteAll, .copyFile, .copyName, .copyPath, .copyText, .copyCalculation,
            .quickLook, .openInApp, .showDetails, .toggleFavorite, .hideFromSearch, .newItem, .settings,
            .edit, .duplicate, .showInFinder:
            true
        case .commandDelete, .pasteFile, .quit, .forceQuit, .restart, .pin, .favoriteSlot,
            .continueInChat:
            false
        }
    }
}
