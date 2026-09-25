import AppKit

/// Owns summoning the palette and nothing else; where and how big stays with the controller.
@MainActor
final class PaletteCoordinator {
    private let palette: PaletteState
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let fileSearch: FileSearchSession
    private let menuSearch: MenuSearchSession
    private let windowSwitch: WindowSwitchSession
    private let windowController: PaletteWindowController
    /// Features whose launcher rows are read from outside Tinycast re-read them on each open.
    var onLauncherShown: (() -> Void)?
    /// Screens that snapshot other apps re-read them on every open, a restored one included.
    var onScreenOpening: ((PaletteMode) -> Void)?

    init(
        palette: PaletteState,
        settings: AppSettings,
        appIndex: AppIndex,
        fileSearch: FileSearchSession,
        menuSearch: MenuSearchSession,
        windowSwitch: WindowSwitchSession,
        windowController: PaletteWindowController
    ) {
        self.palette = palette
        self.settings = settings
        self.appIndex = appIndex
        self.fileSearch = fileSearch
        self.menuSearch = menuSearch
        self.windowSwitch = windowSwitch
        self.windowController = windowController
    }

    // MARK: - Palette control

    var isVisible: Bool { windowController.isVisible }

    var panelFrame: CGRect? { windowController.visibleFrame }

    /// The app an action acts on: the one displaced, else what a hotkey found frontmost.
    var targetApp: NSRunningApplication? {
        windowController.isVisible
            ? windowController.previousApp : NSWorkspace.shared.frontmostApplication
    }

    /// The own window the palette covered, for anything acting on it after the palette hides.
    var previousOwnWindow: NSWindow? { windowController.previousOwnWindow }

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

    /// Navigating keeps the screen under as the back step; the launcher is the root and never has one.
    func navigate(to mode: PaletteMode) {
        if windowController.isVisible, palette.mode != mode, mode != .launcher {
            palette.push(mode: mode)
        } else {
            palette.prepare(mode: mode)
        }
    }

    /// Shows the palette, honoring Pop to Root Search. See docs/features/palette.md#state-flow.
    func showPalette(
        mode: PaletteMode, restoreAnyMode: Bool = false, seeding query: String? = nil
    ) {
        let preserved = windowController.consumePreservedState()
        let restoring = preserved && (restoreAnyMode || palette.mode == mode)
        // Resetting a screen the pop to root already reset would only re-render the whole palette.
        let alreadyFresh = windowController.isPoppedToRoot && palette.mode == mode
        // A carried query always opens the screen fresh: restoring the previous one would drop it.
        if query != nil || !(restoring || alreadyFresh) {
            navigate(to: mode)
        }
        if let query { palette.query = query }
        // Before the show: `targetApp` must still name the app in front, and no row may pop in.
        onScreenOpening?(palette.mode)
        windowController.show()
        if palette.mode == .fileSearch { fileSearch.search(palette.query) }
        if palette.mode == .menuSearch { menuSearch.filter(palette.query) }
        if palette.mode == .switchWindows { windowSwitch.filter(palette.query) }
        // Re-scan on open so an app uninstalled since the last scan drops out of the launcher.
        if palette.mode == .launcher {
            Task { await appIndex.refresh() }
            onLauncherShown?()
        }
    }

    /// Root search onto `entry` alone, as Raycast opens a command whose shortcut lacks values.
    func showArguments(of entry: AppEntry, values: [String: String]) {
        showPalette(mode: .launcher, seeding: entry.name)
        // After the show: `prepare` runs inside it and would clear everything set beforehand.
        palette.argumentEntryID = entry.id
        for (field, value) in values {
            palette.commandArguments[PaletteState.argumentKey(entry.id, field)] = value
        }
        palette.pendingArgumentEntryID = entry.id
    }

    func hidePalette(restoreFocus: Bool = true) {
        fileSearch.cancel()
        menuSearch.reset()
        windowSwitch.reset()
        windowController.hide(restoreFocus: restoreFocus)
    }

    /// A row dragged out and landed is a finished errand, so the palette leaves as after a paste.
    func dragLanded() {
        hidePalette(restoreFocus: false)
    }

    /// Reset to the root search now rather than after the Pop to Root Search delay.
    func popToRootNow() {
        windowController.popToRootNow()
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
