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
        favorites: FavoriteActions, onResetRanking: @escaping () -> Void,
        onHideFromSearch: @escaping () -> Void
    ) -> PopoverMenuContent {
        var items = leadingItems(app: app, searchQuery: searchQuery, core: core)
        // A query-driven row lives only for its query, so no preference could outlive it.
        let isPersistent = !CommandCatalog.isQueryDriven(app)
        if isPersistent {
            items.append(
                PopoverMenuItem(
                    title: favorites.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: favorites.isFavorite ? "star.slash" : "star", startsSection: true,
                    shortcut: "⇧⌘F", action: favorites.toggle))
        }
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
        // These carry their own Show in root search switch rather than a pane checkbox.
        let hidesFromRoot = app.kind == .quicklink || app.kind == .customCommand
        if isPersistent, app.canHideFromSearch || hidesFromRoot {
            let title = hidesFromRoot ? "Hide from Root Search" : "Hide from Search"
            items.append(
                PopoverMenuItem(
                    title: title, systemImage: "eye.slash", shortcut: "⇧⌘H", action: onHideFromSearch))
        }
        if running, app.kind == .application {
            items.append(
                PopoverMenuItem(
                    title: "Restart Application", systemImage: "arrow.clockwise", startsSection: true,
                    shortcut: "⌘R"
                ) {
                    core.launcherCoordinator.restart(app)
                })
            items.append(
                PopoverMenuItem(
                    title: "Quit Application", systemImage: "power", shortcut: "⌃⇧Q"
                ) {
                    core.launcherCoordinator.quit(app)
                })
            items.append(
                PopoverMenuItem(
                    title: "Force Quit Application", systemImage: "xmark.circle", shortcut: "⌃⌥⇧Q"
                ) {
                    core.launcherCoordinator.quit(app, force: true)
                })
        }
        if app.kind == .application {
            items.append(
                PopoverMenuItem(
                    title: "Uninstall Application", systemImage: "trash", startsSection: true,
                    isDestructive: true
                ) {
                    core.uninstallCoordinator.beginUninstall(app)
                })
        }
        if app.kind == .quicklink, let quicklink = core.quicklinks.quicklink(entryID: app.id) {
            items.append(
                PopoverMenuItem(
                    title: "Edit Quicklink", systemImage: "pencil", startsSection: true, shortcut: "⌘E"
                ) {
                    core.quicklinkCoordinator.editQuicklink(quicklink)
                })
        }
        if app.kind == .extensionCommand {
            if core.extensions.isBackgroundSchedulable(for: app) {
                let enabled = core.extensions.isBackgroundEnabled(for: app)
                items.append(
                    PopoverMenuItem(
                        title: enabled ? "Disable Background Refresh" : "Enable Background Refresh",
                        systemImage: enabled ? "pause.circle" : "play.circle", startsSection: true
                    ) {
                        core.extensions.toggleBackgroundRefresh(for: app)
                    })
                if enabled {
                    items.append(
                        PopoverMenuItem(title: "Refresh Now", systemImage: "arrow.clockwise") {
                            core.extensions.refreshNow(app)
                        })
                }
            }
            items.append(
                PopoverMenuItem(
                    title: "Configure Extension", systemImage: "slider.horizontal.3", startsSection: true
                ) {
                    core.extensionCoordinator.showExtensionSettings(for: app)
                })
            items.append(
                PopoverMenuItem(title: "Uninstall Extension", systemImage: "trash", isDestructive: true) {
                    core.extensionCoordinator.confirmUninstall(app)
                })
        }
        return PopoverMenuContent(header: app.name, items: items)
    }

    /// A meeting row leads with the same actions as the meeting's card.
    private static func leadingItems(
        app: AppEntry, searchQuery: String, core: AppCore
    ) -> [PopoverMenuItem] {
        if app.kind == .meeting, let meeting = core.calendarCoordinator.meeting(entryID: app.id) {
            return MeetingActionsMenu.content(meeting: meeting, core: core).items
        }
        let primarySymbol =
            switch app.kind {
            case .application, .command, .extensionCommand: "list.dash.header.rectangle"
            default: "list.bullet.rectangle"
            }
        var items = [
            PopoverMenuItem(
                title: app.kind.descriptor.openVerb, systemImage: primarySymbol,
                shortcut: "↵"
            ) { core.launcherCoordinator.launch(app, searchQuery: searchQuery) }
        ]
        if app.canRevealInFinder {
            items.append(
                PopoverMenuItem(title: "Show in Finder", systemImage: "folder", shortcut: "⌘↵") {
                    core.launcherCoordinator.showInFinder(app)
                })
        }
        return items
    }
}
