import SwiftUI

extension View {
    /// Every store a palette surface reads. Shared so a second hosted hierarchy — the ⌘K menu's
    /// own window — cannot drift from the palette's own.
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
            .environment(core.snippetsStore)
            .environment(core.extensions)
            .environment(core.calendarStore)
            .environment(core.meetingClock)
    }
}
