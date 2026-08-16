import AppKit

/// Owns clipboard-history actions: paste, copy, reveal, pin — and the selection that follows.
@MainActor
final class ClipboardCoordinator {
    private let clipboardStore: ClipboardStore
    private let palette: PaletteState
    private let windowController: PaletteWindowController
    private let paletteCoordinator: PaletteCoordinator
    /// Dialogs, for the one action here that can't be undone.
    private unowned let core: AppCore

    init(
        clipboardStore: ClipboardStore,
        palette: PaletteState,
        windowController: PaletteWindowController,
        paletteCoordinator: PaletteCoordinator,
        core: AppCore
    ) {
        self.clipboardStore = clipboardStore
        self.palette = palette
        self.windowController = windowController
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    /// The setting names an age, the store enforces it; a shortened window culls straight away.
    func applyRetention(_ retention: ClipboardRetention) {
        clipboardStore.maxAge = retention.maxAge
        clipboardStore.enforceLimits()
    }

    func paste(_ item: ClipboardItem) {
        let previous = windowController.previousApp
        paletteCoordinator.hidePalette(restoreFocus: false)
        // A write promotes the item, so follow it and keep the moved row highlighted.
        if Paster.paste(item, store: clipboardStore, previousApp: previous) {
            selectClip(item)
        }
    }

    func pasteKeepingWindowOpen(_ item: ClipboardItem) {
        if windowController.pasteKeepingWindowOpen(item, store: clipboardStore) {
            selectClip(item)
        }
    }

    /// Both the ⌃⇧X chord and the menu row land here, so neither can skip the confirmation.
    func deleteAllClips() async {
        guard
            await core.confirm(
                title: "Clear clipboard history?",
                message: "Every entry goes, pinned ones included. This can't be undone.",
                symbol: PaletteMode.clipboard.systemImage, confirmTitle: "Clear History")
        else { return }
        clipboardStore.clearAll()
    }

    func copyToClipboard(_ item: ClipboardItem) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        if Paster.copy(item, store: clipboardStore) {
            selectClip(item)
        }
    }

    func revealClipboardImage(_ item: ClipboardItem) {
        guard let url = clipboardStore.imageURL(for: item) else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(url)
    }

    /// Pin or unpin an entry; the selection and scroll follow the row as it moves.
    func togglePinnedClip(_ item: ClipboardItem) {
        clipboardStore.togglePinned(item)
        selectClip(item)
        palette.followToken = UUID()
    }

    /// Select `item`'s row as currently filtered; a moved row isn't always index 0.
    private func selectClip(_ item: ClipboardItem) {
        palette.selection =
            clipboardStore.rowIndex(
                of: item, in: palette.query, filter: palette.clipboardFilter) ?? 0
    }
}
