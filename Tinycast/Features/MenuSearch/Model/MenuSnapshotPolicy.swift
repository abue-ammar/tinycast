import Foundation

enum MenuSnapshotPolicy {
    static let maxDepth = 20
    // Sized from live menus: Safari holds ~2,800 leaves, so this keeps giant bars whole.
    static let itemLimit = 4_000

    static func collect(
        _ roots: [MenuTreeNode], isCancelled: () -> Bool = { false }
    ) -> [MenuSearchItem] {
        var items: [MenuSearchItem] = []
        var seen: Set<String> = []
        collect(
            nodes: roots, trail: [], depth: 0, isCancelled: isCancelled, into: &items,
            seen: &seen)
        return items
    }

    private static func collect(
        nodes: [MenuTreeNode], trail: [String], depth: Int,
        isCancelled: () -> Bool, into items: inout [MenuSearchItem], seen: inout Set<String>
    ) {
        guard depth < maxDepth else { return }
        for node in nodes {
            guard !isCancelled(), items.count < itemLimit else { return }
            guard !node.children.isEmpty else {
                // A collapsed submenu exposes no children, so no visible leaf exists to emit.
                if !node.hasSubmenu,
                    MenuSearchItem.isEligible(
                        title: node.title, isEnabled: node.isEnabled, isHidden: node.isHidden,
                        isSeparator: node.isSeparator, canPress: node.canPress)
                {
                    let item = MenuSearchItem(
                        title: node.title, parentComponents: trail,
                        shortcut: node.shortcut)
                    // Real menus repeat an exact path; the palette needs one row per id.
                    if seen.insert(item.id).inserted { items.append(item) }
                }
                continue
            }
            // A parent opens its submenu; it never counts as an activatable leaf.
            var subtrail = trail
            if !node.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                subtrail.append(node.title)
            }
            collect(
                nodes: node.children, trail: subtrail, depth: depth + 1,
                isCancelled: isCancelled, into: &items, seen: &seen)
        }
    }
}
