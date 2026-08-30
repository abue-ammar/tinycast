import AppKit

/// Owns summoning the palette and nothing else; where and how big stays with the controller.
@MainActor
final class PaletteCoordinator {
    private let palette: PaletteState
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let fileSearch: FileSearchSession
    private let windowController: PaletteWindowController

    init(
        palette: PaletteState,
        settings: AppSettings,
        appIndex: AppIndex,
        fileSearch: FileSearchSession,
        windowController: PaletteWindowController
    ) {
        self.palette = palette
        self.settings = settings
        self.appIndex = appIndex
        self.fileSearch = fileSearch
        self.windowController = windowController
    }

    // MARK: - Palette control

    var isVisible: Bool { windowController.isVisible }

    /// The app an action acts on: the one displaced, else what a hotkey found frontmost.
    var targetApp: NSRunningApplication? {
        windowController.isVisible
            ? windowController.previousApp : NSWorkspace.shared.frontmostApplication
    }

    /// Up and pointed at `mode`, which is the state a mode command's second invocation closes.
    func isShowing(_ mode: PaletteMode) -> Bool {
        windowController.isVisible && palette.mode == mode
    }

    func togglePalette() {
        if isShowing(.launcher) {
            hidePalette()
        } else {
            showPalette(mode: .launcher, restoreAnyMode: true)
        }
    }

    /// A carried query always opens: it is new input, not the second press that would close.
    func togglePalette(mode: PaletteMode, seeding query: String? = nil) {
        if isShowing(mode), query == nil {
            hidePalette()
        } else {
            showPalette(mode: mode, seeding: query)
        }
    }

    /// Shows the palette, honoring Pop to Root Search. See docs/features/palette.md#state-flow.
    func showPalette(
        mode: PaletteMode, restoreAnyMode: Bool = false, seeding query: String? = nil
    ) {
        let preserved = windowController.consumePreservedState()
        // A carried query always opens fresh: restoring the previous screen would drop it.
        if let query {
            palette.prepare(mode: mode)
            palette.query = query
        } else if !(preserved && (restoreAnyMode || palette.mode == mode)) {
            palette.prepare(mode: mode)
        }
        windowController.show()
        if palette.mode == .fileSearch { fileSearch.search(palette.query) }
        // Re-scan on open so an app uninstalled since the last scan drops out of the launcher.
        if palette.mode == .launcher { Task { await appIndex.refresh() } }
    }

    func hidePalette(restoreFocus: Bool = true) {
        fileSearch.cancel()
        windowController.hide(restoreFocus: restoreFocus)
    }

    /// True for the slim compact bar: compact on, launcher root, empty, not overflowed.
    var paletteIsCollapsed: Bool {
        settings.compactMode
            && !palette.forceExpanded
            && palette.mode == .launcher
            && palette.query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The compact bar's overflow: expand into the full launcher without typing.
    func expandFromCompact() {
        palette.forceExpanded = true
    }

    /// Resize the panel to the current collapsed state, when it flips while open.
    func syncPaletteSize() {
        windowController.applyCollapsed(paletteIsCollapsed)
    }

    // MARK: - Dragging

    /// Bracket one drag gesture; the handle tracks it from mouse-down to mouse-up itself.
    func beginPaletteDrag() {
        windowController.beginDrag()
    }

    func endPaletteDrag() {
        windowController.endDrag()
    }
}
