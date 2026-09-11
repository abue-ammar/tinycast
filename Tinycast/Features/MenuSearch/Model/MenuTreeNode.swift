import Foundation

struct MenuTreeNode: Hashable, Sendable {
    let title: String
    let isEnabled: Bool
    let isHidden: Bool
    let isSeparator: Bool
    let canPress: Bool
    let hasSubmenu: Bool
    let shortcut: MenuSearchShortcut?
    let children: [MenuTreeNode]

    init(
        title: String, isEnabled: Bool = true, isHidden: Bool = false, isSeparator: Bool = false,
        canPress: Bool = true, hasSubmenu: Bool = false, shortcut: MenuSearchShortcut? = nil,
        children: [MenuTreeNode] = []
    ) {
        self.title = title
        self.isEnabled = isEnabled
        self.isHidden = isHidden
        self.isSeparator = isSeparator
        self.canPress = canPress
        self.hasSubmenu = hasSubmenu
        self.shortcut = shortcut
        self.children = children
    }
}
