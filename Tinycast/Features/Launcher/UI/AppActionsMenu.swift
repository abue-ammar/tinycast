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
                title: String(localized: String.LocalizationValue(app.kind.descriptor.openVerb), bundle: .appLanguage),
                systemImage: "list.bullet.rectangle",
                shortcut: "↵"
            ) { core.launcherCoordinator.launch(app, searchQuery: searchQuery) }
        ]
        // A query-driven row lives only for its query, so pinning it would favorite nothing.
        if !CommandCatalog.isQueryDriven(app) {
            items.append(
                PopoverMenuItem(
                    title: favorites.isFavorite
                        ? String(
                            localized: "Remove from Favorites",
                            bundle: .appLanguage) : String(
                            localized: "Add to Favorites",
                            bundle: .appLanguage),
                    systemImage: favorites.isFavorite ? "star.slash" : "star", shortcut: "⇧⌘F",
                    action: favorites.toggle))
        }
        if favorites.canMoveUp {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Move Favorite Up", bundle: .appLanguage), systemImage: "arrow.up", shortcut: "⌥⌘↑"
                ) {
                    favorites.move(-1)
                })
        }
        if favorites.canMoveDown {
            items.append(
                PopoverMenuItem(
                    title: String(
                        localized: "Move Favorite Down",
                        bundle: .appLanguage), systemImage: "arrow.down", shortcut: "⌥⌘↓"
                ) {
                    favorites.move(1)
                })
        }
        if core.launcherRanking.hasRanking(for: app.preferenceKey) {
            items.append(
                PopoverMenuItem(title: String(
                    localized: "Reset Ranking",
                    bundle: .appLanguage), systemImage: "arrow.counterclockwise") {
                    onResetRanking()
                })
        }
        if app.canRevealInFinder {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Show in Finder", bundle: .appLanguage), systemImage: "folder", shortcut: "⌘↵"
                ) {
                    core.launcherCoordinator.showInFinder(app)
                })
        }
        if running, app.kind == .application {
            items.append(
                PopoverMenuItem(
                    title: String(
                        localized: "Restart Application",
                        bundle: .appLanguage), systemImage: "arrow.clockwise", shortcut: "⌘R"
                ) {
                    core.launcherCoordinator.restart(app)
                })
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Quit Application", bundle: .appLanguage), systemImage: "power", shortcut: "⌃⇧Q",
                    isDestructive: true
                ) {
                    core.launcherCoordinator.quit(app)
                })
        }
        if app.kind == .application {
            items.append(
                PopoverMenuItem(
                    title: String(
                        localized: "Uninstall Application",
                        bundle: .appLanguage), systemImage: "trash", isDestructive: true
                ) {
                    core.uninstallCoordinator.beginUninstall(app)
                })
        }
        if app.kind == .extensionCommand {
            if core.extensions.isBackgroundSchedulable(for: app) {
                let enabled = core.extensions.isBackgroundEnabled(for: app)
                items.append(
                    PopoverMenuItem(
                        title: enabled
                            ? String(localized: "Disable Background Refresh", bundle: .appLanguage)
                            : String(localized: "Enable Background Refresh", bundle: .appLanguage),
                        systemImage: enabled ? "pause.circle" : "play.circle"
                    ) {
                        core.extensions.toggleBackgroundRefresh(for: app)
                    })
                if enabled {
                    items.append(
                        PopoverMenuItem(title: String(
                            localized: "Refresh Now",
                            bundle: .appLanguage), systemImage: "arrow.clockwise") {
                            core.extensions.refreshNow(app)
                        })
                }
            }
            items.append(
                PopoverMenuItem(title: String(
                    localized: "Configure Extension",
                    bundle: .appLanguage), systemImage: "slider.horizontal.3") {
                    core.extensionCoordinator.showExtensionSettings(for: app)
                })
            items.append(
                PopoverMenuItem(
                    title: String(
                        localized: "Uninstall Extension",
                        bundle: .appLanguage), systemImage: "trash", isDestructive: true
                ) {
                    core.extensionCoordinator.confirmUninstall(app)
                })
        }
        return PopoverMenuContent(header: app.localizedName, items: items)
    }
}
