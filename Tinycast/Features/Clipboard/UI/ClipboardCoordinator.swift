import AppKit

/// Owns clipboard-history actions: paste, copy, reveal, pin — and the selection that follows.
@MainActor
final class ClipboardCoordinator {
    private let clipboardStore: ClipboardStore
    private let clipboardManager: ClipboardManager
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let palette: PaletteState
    private let windowController: PaletteWindowController
    private let paletteCoordinator: PaletteCoordinator
    /// Dialogs, for the one action here that can't be undone.
    private unowned let core: AppCore

    init(
        clipboardStore: ClipboardStore,
        clipboardManager: ClipboardManager,
        settings: AppSettings,
        appIndex: AppIndex,
        palette: PaletteState,
        windowController: PaletteWindowController,
        paletteCoordinator: PaletteCoordinator,
        core: AppCore
    ) {
        self.clipboardStore = clipboardStore
        self.clipboardManager = clipboardManager
        self.settings = settings
        self.appIndex = appIndex
        self.palette = palette
        self.windowController = windowController
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    /// Off means the poller stops, the database closes and nothing new is ever recorded.
    func applyEnabled() {
        appIndex.setCommandsVisible([.clipboardHistory], settings.clipboardEnabled)
        guard settings.clipboardEnabled else {
            core.applyClipboardTextSearch()
            clipboardManager.stop()
            if palette.mode == .clipboard { palette.prepare(mode: .launcher) }
            clipboardStore.close()
            return
        }
        clipboardStore.open()
        clipboardStore.maxAge = settings.clipboardRetention.maxAge
        clipboardManager.start()
        core.applyClipboardTextSearch()
        // Deferred off the launch path: the palette fills in behind the SQLite read and prune.
        Task { clipboardStore.load() }
    }

    func followSearchResults(query: String, previous: [ClipboardItem], current: [ClipboardItem]) {
        guard palette.isVisible, palette.mode == .clipboard,
            palette.query.trimmingCharacters(in: .whitespaces) == query,
            previous.indices.contains(palette.selection)
        else { return }
        let selectedID = previous[palette.selection].id
        if let index = current.firstIndex(where: { $0.id == selectedID }) {
            palette.selection = index
        }
    }

    /// The setting names an age, the store enforces it; a shortened window culls straight away.
    func applyRetention(_ retention: ClipboardRetention) {
        clipboardStore.maxAge = retention.maxAge
        clipboardStore.enforceLimits()
    }

    /// ↵ runs the configured default and the other chords follow it; false when `chord` has none.
    @discardableResult
    func activate(_ item: ClipboardItem, chord: ClipboardChord = .return) -> Bool {
        guard let action = settings.clipboardDefaultAction.action(for: chord, on: item) else {
            return false
        }
        perform(action, on: item)
        return true
    }

    func perform(_ action: ClipboardDefaultAction, on item: ClipboardItem) {
        switch action {
        case .paste: paste(item)
        case .copy: copyToClipboard(item)
        case .pastePlainText: pasteAsPlainText(item)
        }
    }

    func paste(_ item: ClipboardItem) {
        let previous = windowController.previousApp
        paletteCoordinator.hidePalette(restoreFocus: false)
        // A write promotes the item, so follow it and keep the moved row highlighted.
        if Paster.paste(item, store: clipboardStore, previousApp: previous) {
            selectClip(item)
        } else {
            reportUnavailable(item)
        }
    }

    /// A file's path stays valid text after the file goes, so this never reports it missing.
    func pasteAsPlainText(_ item: ClipboardItem) {
        let previous = windowController.previousApp
        paletteCoordinator.hidePalette(restoreFocus: false)
        if Paster.pastePlainText(item, store: clipboardStore, previousApp: previous) {
            selectClip(item)
        }
    }

    func pasteKeepingWindowOpen(_ item: ClipboardItem) {
        if windowController.pasteKeepingWindowOpen(item, store: clipboardStore) {
            selectClip(item)
        } else {
            reportUnavailable(item)
        }
    }

    /// A vanished file is the only failure, and a palette that just closes explains nothing.
    private func reportUnavailable(_ item: ClipboardItem) {
        guard item.kind == .file else { return }
        core.showMessage("That file has moved or been deleted.", tone: .danger)
    }

    /// Both the ⌃⇧X chord and the menu row land here, so neither can skip the confirmation.
    func deleteAllClips() async {
        guard
            await core.confirm(
                title: "Delete All Entries",
                message: "Are you sure you want to proceed with deleting all clipboard history entries?",
                symbol: PaletteMode.clipboard.systemImage, confirmTitle: "Delete All")
        else { return }
        clearHistory()
    }

    /// Reachable with the feature off, so what was kept before can still be erased afterwards.
    func clearHistory() {
        clipboardStore.open()
        clipboardStore.clearAll()
        if !settings.clipboardEnabled { clipboardStore.close() }
    }

    func copyToClipboard(_ item: ClipboardItem) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        if Paster.copy(item, store: clipboardStore) {
            selectClip(item)
        } else {
            reportUnavailable(item)
        }
    }

    /// Unmarked, so a converted colour enters history itself — it is one you meant to keep.
    func copyColor(_ color: ColorValue, as format: ColorFormat) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyPlainText(format.string(for: color))
    }

    func revealClip(_ item: ClipboardItem) {
        guard let url = clipURL(for: item) else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(url)
    }

    /// Nil only for a vanished file, which the HUD reports rather than hand over a dead path.
    func dragPayload(for item: ClipboardItem) -> ClipDragPayload? {
        let payload = item.dragPayload
        guard case .file = payload else { return payload }
        return clipURL(for: item).map(ClipDragPayload.file)
    }

    func openClip(_ item: ClipboardItem) {
        guard let url = clipURL(for: item) else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        AppLauncher.open(url)
    }

    /// Unmarked, so the path enters history like any other copy the reader meant to make.
    func copyClipPath(_ item: ClipboardItem) {
        guard let path = item.filePath else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyPlainText(path)
        core.showMessage("Copied path")
    }

    /// ⇧⌘T / “Copy Text” — OCRs the image in the bundled helper and copies what it reads.
    func copyImageText(_ item: ClipboardItem) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        guard textImageURL(for: item) != nil else { return }
        core.showProgress("Reading text…")
        Task {
            do {
                let text = try await ClipboardTextWorker.extract(item)
                guard !text.isEmpty else {
                    core.showMessage("No text found", tone: .neutral)
                    return
                }
                Paster.copyPlainText(text)
                core.showMessage("Copied text")
            } catch {
                core.showMessage("Couldn’t read the text", tone: .danger)
            }
        }
    }

    /// The file OCR reads, stat-checked so a vanished row raises the HUD its kind already uses.
    private func textImageURL(for item: ClipboardItem) -> URL? {
        let url = item.kind == .image ? clipboardStore.imageURL(for: item)
            : clipboardStore.fileURL(for: item)
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            if item.kind == .file { reportUnavailable(item) }
            else { core.showMessage("That image is no longer available.", tone: .danger) }
            return nil
        }
        return url
    }

    /// Nil once the file is gone, so every action reports rather than silently no-opping.
    private func clipURL(for item: ClipboardItem) -> URL? {
        let url = clipboardStore.imageURL(for: item) ?? clipboardStore.fileURL(for: item)
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            reportUnavailable(item)
            return nil
        }
        return url
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
