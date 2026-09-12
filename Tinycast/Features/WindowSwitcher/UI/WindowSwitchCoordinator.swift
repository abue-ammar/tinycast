import AppKit

@MainActor
final class WindowSwitchCoordinator {
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let session: WindowSwitchSession
    private let palette: PaletteState
    private let paletteCoordinator: PaletteCoordinator
    private unowned let core: AppCore

    init(
        settings: AppSettings, appIndex: AppIndex, session: WindowSwitchSession,
        palette: PaletteState, paletteCoordinator: PaletteCoordinator, core: AppCore
    ) {
        self.settings = settings
        self.appIndex = appIndex
        self.session = session
        self.palette = palette
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    func applyEnabled() {
        appIndex.setCommandsVisible([.switchWindows], settings.navigationEnabled)
        guard !settings.navigationEnabled else { return }
        session.reset()
        if palette.mode == .switchWindows { palette.prepare(mode: .launcher) }
    }

    func show() {
        guard settings.navigationEnabled else { return }
        guard Permissions.ensureAccessibility() else {
            Task { await self.reportPermissionFailure() }
            return
        }
        session.present(WindowSwitchSweep.snapshot(ranks: WindowZOrder.appRanks()))
        paletteCoordinator.togglePalette(mode: .switchWindows)
    }

    func activate(_ entry: WindowSwitchEntry) {
        guard Permissions.ensureAccessibility() else {
            Task { await self.reportPermissionFailure() }
            return
        }
        // Resolved before the hide: hiding resets the session, which drops the element table.
        guard let element = session.element(for: entry.handle), !element.app.isTerminated else {
            Task { await self.reportGone(entry) }
            return
        }
        // Restoring focus reactivates the displaced app, which races the raise below.
        paletteCoordinator.hidePalette(restoreFocus: false)
        if entry.isMinimized { _ = AXWindowAccess.unminimize(element.window) }
        _ = AXWindowAccess.raise(element.window)
        AXWindowAccess.makeFrontmost(element.application)
        element.app.activate()
    }

    // MARK: - Reporting

    private func reportPermissionFailure() async {
        let openSettings = await core.reportFailure(
            title: "Tinycast Needs Accessibility Access",
            message: "Switching windows reads and raises other apps' windows.",
            symbol: "macwindow.on.rectangle", recovery: "Open Settings")
        if openSettings { Permissions.openAccessibilitySettings() }
    }

    private func reportGone(_ entry: WindowSwitchEntry) async {
        await core.showNotice(
            title: "Couldn’t Switch to “\(entry.displayTitle)”",
            message: "It closed before the switch landed. Search again and retry.",
            symbol: "macwindow.on.rectangle", tone: .danger)
    }
}
