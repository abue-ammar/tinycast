import AppKit

/// Owns emoji delivery: frequency tallies the base glyph, the configured tone applies at copy time.
@MainActor
final class EmojiCoordinator {
    private let frequentEmoji: FrequentEmojiStore
    private let settings: AppSettings
    private let windowController: PaletteWindowController
    private let paletteCoordinator: PaletteCoordinator

    init(
        frequentEmoji: FrequentEmojiStore,
        settings: AppSettings,
        windowController: PaletteWindowController,
        paletteCoordinator: PaletteCoordinator
    ) {
        self.frequentEmoji = frequentEmoji
        self.settings = settings
        self.windowController = windowController
        self.paletteCoordinator = paletteCoordinator
    }

    func pasteEmoji(_ entry: EmojiEntry) {
        frequentEmoji.record(entry.glyph)
        let previous = windowController.previousApp
        leaveAfterPick()
        Paster.pasteString(entry.display(tone: settings.emojiSkinTone), previousApp: previous)
    }

    func copyEmoji(_ entry: EmojiEntry) {
        frequentEmoji.record(entry.glyph)
        leaveAfterPick()
        Paster.copyString(entry.display(tone: settings.emojiSkinTone))
    }

    /// A pick is the picker's whole errand, so by default Pop to Root Search has nothing to keep.
    private func leaveAfterPick() {
        paletteCoordinator.hidePalette(restoreFocus: false)
        if settings.emojiPopsToRootAfterPick { paletteCoordinator.popToRootNow() }
    }

    func pasteEmojiKeepingWindowOpen(_ entry: EmojiEntry) {
        frequentEmoji.record(entry.glyph)
        windowController.pasteStringKeepingWindowOpen(entry.display(tone: settings.emojiSkinTone))
    }
}
