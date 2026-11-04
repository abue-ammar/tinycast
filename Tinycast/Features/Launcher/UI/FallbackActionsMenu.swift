import Foundation

/// Actions for one fallback row. It answers the query rather than naming a thing, so nothing
/// here pins or reveals it — the two entries are running it and changing the list.
@MainActor
enum FallbackActionsMenu {
    static func content(
        fallback: Fallback, entry: AppEntry, core: AppCore, onRun: @escaping () -> Void
    ) -> PopoverMenuContent {
        PopoverMenuContent(
            header: entry.name,
            items: [
                PopoverMenuItem(
                    title: fallback.openVerb, systemImage: "list.bullet.rectangle", shortcut: "↵",
                    action: onRun),
                PopoverMenuItem(
                    title: String(localized: "Configure Fallbacks…"), systemImage: "slider.horizontal.3",
                    startsSection: true
                ) {
                    core.fallbackCoordinator.showSettings()
                }
            ])
    }
}
