import Foundation

extension HotKeyAction {
    /// A row's action from its ID alone; apps and panes are keyed by bundle ID instead.
    init?(entryID: String) {
        if let command = CommandID(rawValue: entryID) {
            guard let action = command.hotKeyAction else { return nil }
            self = action
        } else if let action = SystemActionCatalog.action(forEntryID: entryID) {
            self = .systemAction(id: action.id)
        } else if let command = WindowCommandCatalog.command(forEntryID: entryID) {
            self = .windowCommand(id: command.id)
        } else if let id = CustomWindowSize.id(fromEntryID: entryID) {
            self = .customWindowSize(id: id)
        } else if let id = WindowLayout.id(fromEntryID: entryID) {
            self = .windowLayout(id: id)
        } else if let id = Room.id(fromEntryID: entryID) {
            self = .windowRoom(id: id)
        } else if let id = CustomQuickAction.id(fromEntryID: entryID) {
            self = .quickAction(id: id)
        } else if let id = CustomCommand.id(fromEntryID: entryID) {
            self = .customCommand(id: id)
        } else if let id = Quicklink.id(fromEntryID: entryID) {
            self = .quicklink(id: id)
        } else if let id = AppleShortcut.id(fromEntryID: entryID) {
            self = .appleShortcut(id: id)
        } else if let id = StoredSnippet.id(fromEntryID: entryID) {
            self = .snippet(id: id)
        } else {
            return nil
        }
    }
}
