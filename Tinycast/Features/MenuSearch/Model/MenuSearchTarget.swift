import Foundation

enum MenuSearchTarget: Hashable, Sendable {
    case searchable(name: String)
    case excluded(name: String)
    case selfTarget
    case menuLess(name: String)
    case noApplication

    static func classify(
        appName: String?, isSelf: Bool, hasMenuBar: Bool, isExcluded: Bool
    ) -> Self {
        guard let appName else { return .noApplication }
        // Tinycast itself runs accessory, so self wins over the menu-bar check below.
        if isSelf { return .selfTarget }
        // Before the menu-bar test, so an excluded accessory app reads as excluded, not menu-less.
        if isExcluded { return .excluded(name: appName) }
        guard hasMenuBar else { return .menuLess(name: appName) }
        return .searchable(name: appName)
    }
}
