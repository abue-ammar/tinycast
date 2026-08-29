import SwiftUI

/// Actions menu for a launcher app, from right-click or the Actions pill.
@MainActor
enum AppActionsMenu {
    /// Resolved by the screen that owns the visible order; every row runs its chord's call.
    @MainActor
    struct FavoriteActions {
        let isFavorite: Bool
        let canMoveUp: Bool
        let canMoveDown: Bool
        let toggle: () -> Void
        let move: (Int) -> Void
    }

    static func content(
        app: AppEntry, searchQuery: String, core: AppCore, running: Bool,
        favorites: FavoriteActions, onResetRanking: @escaping () -> Void
    ) -> PopoverMenuContent {
        var items: [PopoverMenuItem] = [
            PopoverMenuItem(
                title: app.kind.descriptor.openVerb, systemImage: "list.bullet.rectangle",
                shortcut: "↵"
            ) { core.launcherCoordinator.launch(app, searchQuery: searchQuery) }
        ]
        items.append(
            PopoverMenuItem(
                title: favorites.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                systemImage: favorites.isFavorite ? "star.slash" : "star", shortcut: "⇧⌘F",
                action: favorites.toggle))
        if favorites.canMoveUp {
            items.append(
                PopoverMenuItem(
                    title: "Move Favorite Up", systemImage: "arrow.up", shortcut: "⌥⌘↑"
                ) {
                    favorites.move(-1)
                })
        }
        if favorites.canMoveDown {
            items.append(
                PopoverMenuItem(
                    title: "Move Favorite Down", systemImage: "arrow.down", shortcut: "⌥⌘↓"
                ) {
                    favorites.move(1)
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
                    title: "Restart Application", systemImage: "arrow.clockwise", shortcut: "⌘R"
                ) {
                    core.launcherCoordinator.restart(app)
                })
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
