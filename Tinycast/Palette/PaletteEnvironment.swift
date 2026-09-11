import SwiftUI

/// A stored environment value would freeze at panel-build time; a body re-reads under Observation.
private struct InterfaceMetricsScope: ViewModifier {
    let settings: AppSettings

    func body(content: Content) -> some View {
        content.environment(\.metrics, settings.interfaceSize.metrics)
    }
}

extension View {
    /// Shared, so the ⌘K menu's own hosted hierarchy cannot drift from the palette's.
    func paletteEnvironment(_ core: AppCore) -> some View {
        self
            .modifier(InterfaceMetricsScope(settings: core.settings))
            .environment(core)
            .environment(core.settings)
            .environment(core.palette)
            .environment(core.appIndex)
            .environment(core.clipboardStore)
            .environment(core.favorites)
            .environment(core.visibility)
            .environment(core.aliases)
            .environment(core.fallbacks)
            .environment(core.calcHistory)
            .environment(core.currencyRates)
            .environment(core.emojiIndex)
            .environment(core.frequentEmoji)
            .environment(core.fileSearch)
            .environment(core.menuSearch)
            .environment(core.runningApps)
            .environment(core.hotKeys)
            .environment(core.uninstall)
            .environment(core.quicklinks)
            .environment(core.customCommandArguments)
            .environment(core.snippetsStore)
            .environment(core.extensions)
            .environment(core.calendarStore)
            .environment(core.meetingClock)
    }
}
