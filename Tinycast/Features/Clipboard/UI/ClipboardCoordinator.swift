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
    /// One on-demand Extract Text at a time; a second request cancels the first.
    private var extractTask: Task<Void, Never>?

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

    /// ↵ runs the configured default; ⌘↵ the other one, so the two chords stay a swapped pair.
    func activate(_ item: ClipboardItem, inverted: Bool = false) {
        if (settings.clipboardDefaultAction == .copy) != inverted {
            copyToClipboard(item)
        } else {
            paste(item)
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

    func pasteKeepingWindowOpen(_ item: ClipboardItem) {
        if windowController.pasteKeepingWindowOpen(item, store: clipboardStore) {
            selectClip(item)
        } else {
            reportUnavailable(item)
        }
    }

    /// A write only fails on a vanished file, and a palette that just closes explains nothing.
    private func reportUnavailable(_ item: ClipboardItem) {
        guard item.kind == .file else { return }
        core.showMessage("That file has moved or been deleted.", tone: .danger)
    }

    /// Both the ⌃⇧X chord and the menu row land here, so neither can skip the confirmation.
    func deleteAllClips() async {
        guard
            await core.confirm(
                title: "Clear clipboard history?",
                message: "Every entry goes, pinned ones included. This can't be undone.",
                symbol: PaletteMode.clipboard.systemImage, confirmTitle: "Clear History")
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

    /// A landed drop is a finished errand, so the palette leaves as it does after a paste.
    func clipDropped() {
        paletteCoordinator.hidePalette(restoreFocus: false)
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

    /// Image, PDF, or a plain-text-ish file — anything Extract Text can turn into prose.
    func canExtractText(_ item: ClipboardItem) -> Bool {
        switch item.kind {
        case .image: return true
        case .file:
            guard let path = item.filePath else { return false }
            let kind = ClipboardFileKind.of(path: path)
            return kind == .image || kind == .pdf
                || ClipboardFileKind.isPlainTextReadable(path: path)
        case .text: return false
        }
    }

    /// Pull prose onto the pasteboard; Vision/PDF stay in `ClipboardTextHelper`.
    func extractText(from item: ClipboardItem) {
        startExtract(from: item) { text, core in
            Paster.copyPlainText(text)
            core.showMessage("Text copied to clipboard")
        }
    }

    /// Extract, then hand the pasteboard to a Quick Action the same way a typed rewrite would.
    func extractTextAndApplyAction(from item: ClipboardItem, action: QuickAction) {
        startExtract(from: item) { text, core in
            Paster.copyPlainText(text)
            core.quickActionCoordinator.run(action)
        }
    }

    private func startExtract(
        from item: ClipboardItem, finish: @MainActor @escaping (String, AppCore) -> Void
    ) {
        guard canExtractText(item), let url = clipURL(for: item) else { return }
        extractTask?.cancel()
        core.showProgress("Extracting text…")
        extractTask = Task { [weak self] in
            guard let self else { return }
            defer { self.extractTask = nil }
            do {
                let text = try await Self.pullText(item: item, url: url)
                guard !Task.isCancelled else { return }
                self.core.hideProgress()
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    self.core.showMessage("No text found", tone: .danger)
                    return
                }
                finish(trimmed, self.core)
            } catch {
                guard !Task.isCancelled else { return }
                self.core.hideProgress()
                await self.reportExtractFailure(error)
            }
        }
    }

    private func reportExtractFailure(_ error: Error) async {
        if ClipboardTextWorker.isAccessDenied(error) {
            let open = await core.reportFailure(
                title: "Tinycast can’t read that file",
                message:
                    "macOS blocked access to this folder. Allow Tinycast under "
                    + "Privacy & Security › Files and Folders, then try again.",
                symbol: "folder.badge.questionmark",
                recovery: "Open System Settings…")
            if open { Permissions.openFilesAndFoldersSettings() }
            return
        }
        core.showMessage(error.localizedDescription, tone: .danger)
    }

    private static func pullText(item: ClipboardItem, url: URL) async throws -> String {
        if item.kind == .image {
            return try await ClipboardTextWorker.extract(item)
        }
        guard let path = item.filePath else { return "" }
        let kind = ClipboardFileKind.of(path: path)
        switch kind {
        case .image, .pdf:
            return try await ClipboardTextWorker.extract(item)
        default:
            guard ClipboardFileKind.isPlainTextReadable(path: path) else { return "" }
            return try await Task.detached {
                try ClipboardTextWorker.extractPlainTextFile(at: url)
            }.value
        }
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
