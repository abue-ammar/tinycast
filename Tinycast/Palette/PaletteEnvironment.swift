import SwiftUI

extension View {
    /// Shared, so the ⌘K menu's own hosted hierarchy cannot drift from the palette's.
    func paletteEnvironment(_ core: AppCore) -> some View {
        self
            .environment(core)
            .environment(core.settings)
            .environment(core.palette)
            .environment(core.appIndex)
            .environment(core.clipboardStore)
            .environment(core.favorites)
            .environment(core.visibility)
            .environment(core.aliases)
            .environment(core.calcHistory)
            .environment(core.currencyRates)
            .environment(core.emojiIndex)
            .environment(core.frequentEmoji)
            .environment(core.fileSearch)
            .environment(core.runningApps)
            .environment(core.hotKeys)
            .environment(core.uninstall)
            .environment(core.quicklinks)
            .environment(core.quicklinkArguments)
            .environment(core.customCommandArguments)
            .environment(core.snippetsStore)
            .environment(core.extensions)
            .environment(core.calendarStore)
            .environment(core.meetingClock)
    }
}
