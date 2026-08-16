import SwiftUI

/// Actions menu for a launcher app, from right-click or the Actions pill.
@MainActor
enum AppActionsMenu {
    static func content(
        app: AppEntry, searchQuery: String, core: AppCore, favorites: FavoritesStore,
        running: Bool, onResetRanking: @escaping () -> Void
    ) -> PopoverMenuContent {
        var items: [PopoverMenuItem] = [
            PopoverMenuItem(
                title: app.kind.descriptor.openVerb, systemImage: "list.bullet.rectangle",
                shortcut: "↵"
            ) { core.launcherCoordinator.launch(app, searchQuery: searchQuery) }
        ]
        if favorites.isFavorite(app) {
            items.append(
                PopoverMenuItem(title: "Remove from Favorites", systemImage: "star.slash") {
                    favorites.toggle(app)
                })
        } else {
            items.append(
                PopoverMenuItem(title: "Add to Favorites", systemImage: "star") {
                    favorites.toggle(app)
                })
        }
        if core.launcherRanking.hasRanking(for: app.preferenceKey) {
            items.append(
                PopoverMenuItem(title: "Reset Ranking", systemImage: "arrow.counterclockwise") {
                    onResetRanking()
                })
        }
        if app.canRevealInFinder {
            items.append(
                PopoverMenuItem(
                    title: "Show in Finder", systemImage: "folder", shortcut: "⌘↵"
                ) {
                    core.launcherCoordinator.showInFinder(app)
                })
        }
        if running, app.kind == .application {
            items.append(
                PopoverMenuItem(
                    title: "Quit Application", systemImage: "power", shortcut: "⌃⇧Q",
                    isDestructive: true
                ) {
                    core.launcherCoordinator.quit(app)
                })
        }
        if app.kind == .application {
            items.append(
                PopoverMenuItem(
                    title: "Uninstall Application", systemImage: "trash", isDestructive: true
                ) {
                    core.uninstallCoordinator.beginUninstall(app)
                })
        }
        if app.kind == .extensionCommand {
            items.append(
                PopoverMenuItem(title: "Configure Extension", systemImage: "slider.horizontal.3") {
                    core.extensionCoordinator.showExtensionSettings(for: app)
                })
            items.append(
                PopoverMenuItem(
                    title: "Uninstall Extension", systemImage: "trash", isDestructive: true
                ) {
                    core.extensionCoordinator.confirmUninstall(app)
                })
        }
        return PopoverMenuContent(header: app.name, items: items)
    }
}
