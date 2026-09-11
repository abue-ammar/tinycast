import Foundation

enum MenuSearchTarget: Hashable, Sendable {
    case searchable(name: String)
    case selfTarget
    case menuLess(name: String)
    case noApplication

    static func classify(appName: String?, isSelf: Bool, hasMenuBar: Bool) -> Self {
        guard let appName else { return .noApplication }
        // Tinycast itself runs accessory, so self wins over the menu-bar check below.
        if isSelf { return .selfTarget }
        guard hasMenuBar else { return .menuLess(name: appName) }
        return .searchable(name: appName)
    }
}
