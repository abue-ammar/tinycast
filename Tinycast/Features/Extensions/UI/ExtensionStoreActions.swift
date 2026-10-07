import SwiftUI

@MainActor
enum ExtensionStoreActions {
    static func items(
        listing: ExtensionListing, coordinator: ExtensionStoreCoordinator
    ) -> [PopoverMenuItem] {
        var items: [PopoverMenuItem] = []
        if coordinator.canActivate(listing) {
            items.append(PopoverMenuItem(
                title: coordinator.primaryTitle(for: listing), systemImage: "arrow.down.circle", shortcut: "⌘↵"
            ) { coordinator.activate(listing) })
        }
        if let url = listing.storeURL {
            items.append(PopoverMenuItem(title: "Open in Browser", systemImage: "globe") { coordinator.open(url) })
        }
        if let url = listing.sourceURL {
            items.append(PopoverMenuItem(title: "View Source", systemImage: "chevron.left.forwardslash.chevron.right") {
                coordinator.open(url)
            })
        }
        if let url = listing.readmeURL {
            items.append(PopoverMenuItem(title: "Open README", systemImage: "doc.text") { coordinator.open(url) })
        }
        if coordinator.isInstalled(listing) {
            items.append(PopoverMenuItem(title: "Uninstall Extension", systemImage: "trash", startsSection: true) {
                coordinator.uninstall(listing)
            })
        }
        return items
    }
}
