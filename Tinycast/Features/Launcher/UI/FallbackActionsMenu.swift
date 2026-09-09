import Foundation

/// Actions for one fallback row. It answers the query rather than naming a thing, so nothing
/// here pins, ranks or reveals it — the two entries are running it and changing the list.
@MainActor
enum FallbackActionsMenu {
    static func content(
        fallback: Fallback, entry: AppEntry, query: String, core: AppCore
    ) -> PopoverMenuContent {
        PopoverMenuContent(
            header: entry.localizedName,
            items: [
                PopoverMenuItem(
                    title: String(localized: String.LocalizationValue(fallback.openVerb), bundle: .appLanguage),
                    systemImage: "list.bullet.rectangle", shortcut: "↵"
                ) { core.fallbackCoordinator.run(fallback, query: query) },
                PopoverMenuItem(title: String(
                    localized: "Configure Fallbacks…",
                    bundle: .appLanguage), systemImage: "slider.horizontal.3") {
                    core.fallbackCoordinator.showSettings()
                }
            ])
    }
}
