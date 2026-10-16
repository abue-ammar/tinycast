import AppKit

@MainActor
final class WindowSwitchCoordinator {
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let session: WindowSwitchSession
    private let palette: PaletteState
    private let paletteCoordinator: PaletteCoordinator
    private unowned let core: AppCore
    /// Armed by a repeat press with its modifiers held: letting go switches, as ⌘Tab does.
    private var releaseMonitor: Any?
    private static let chordModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

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
        appIndex.setCommandsVisible(
            [.switchWindows, .switchWindowsBackwards], settings.navigationEnabled)
        guard !settings.navigationEnabled else { return }
        session.reset()
        if palette.mode == .switchWindows { palette.prepare(mode: .launcher) }
    }

    func show(backwards: Bool = false) {
        guard settings.navigationEnabled, hasAccessibility() else { return }
        if paletteCoordinator.isShowing(.switchWindows) { return step(by: backwards ? -1 : 1) }
        disarmSwitchOnRelease()
        paletteCoordinator.togglePalette(mode: .switchWindows)
    }

    /// The first step lands on the window behind the current one, which the list opens on.
    private func step(by offset: Int) {
        let count = session.filtered.count
        guard count > 0 else { return }
        palette.selection = (palette.selection + offset + count) % count
        palette.followToken = UUID()
        armSwitchOnRelease()
    }

    /// A single press still searches: only a held chord, stepped again, switches on release.
    private func armSwitchOnRelease() {
        let held = NSEvent.modifierFlags.intersection(Self.chordModifiers)
        guard !held.isEmpty, releaseMonitor == nil else { return }
        releaseMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] in
            let event = $0
            guard let self, event.modifierFlags.isDisjoint(with: held) else { return event }
            self.switchOnRelease()
            return event
        }
    }

    private func disarmSwitchOnRelease() {
        if let releaseMonitor { NSEvent.removeMonitor(releaseMonitor) }
        releaseMonitor = nil
    }

    private func switchOnRelease() {
        disarmSwitchOnRelease()
        let rows = session.filtered
        guard paletteCoordinator.isShowing(.switchWindows), rows.indices.contains(palette.selection)
        else { return }
        activate(rows[palette.selection])
    }

    /// Every open sweeps anew, a restore included: hiding dropped the last snapshot.
    func load() {
        guard hasAccessibility() else { return }
        session.present(WindowSwitchSweep.snapshot(ranks: WindowZOrder.appRanks()))
    }

    func activate(_ entry: WindowSwitchEntry) {
        guard hasAccessibility() else { return }
        // Resolved before the hide: hiding resets the session, which drops the element table.
        guard let element = liveElement(for: entry) else {
            Task { await self.reportGone(entry) }
            return
        }
        // Restoring focus reactivates the displaced app, which races the raise below.
        paletteCoordinator.hidePalette(restoreFocus: false)
        if entry.isMinimized { _ = AXWindowAccess.unminimize(element.window) }
        AXWindowAccess.focus(element.window, in: element.application, of: element.app)
    }

    /// A full-screen window can't minimize, so its row must not join the minimized ones.
    func minimize(_ entry: WindowSwitchEntry) {
        guard !entry.isMinimized, hasAccessibility(), let element = liveElement(for: entry),
            !AXWindowAccess.isFullScreen(element.window), AXWindowAccess.minimize(element.window)
        else { return }
        session.markMinimized(entry.handle)
    }

    func hideApplication(_ entry: WindowSwitchEntry) {
        guard hasAccessibility(), let element = liveElement(for: entry) else { return }
        // Restoring focus would reactivate, and so unhide, an app hidden from in front.
        paletteCoordinator.hidePalette(restoreFocus: false)
        if !element.app.hide() {
            AXWindowAccess.setHidden(true, application: element.application)
        }
    }

    /// Rows leave when the app exits, so a quit refused by a save sheet keeps them.
    func quitApplication(_ entry: WindowSwitchEntry) {
        liveElement(for: entry)?.app.terminate()
    }

    private func liveElement(for entry: WindowSwitchEntry) -> WindowSwitchSweep.Element? {
        guard let element = session.element(for: entry.handle), !element.app.isTerminated
        else { return nil }
        return element
    }

    private func hasAccessibility() -> Bool {
        guard Permissions.ensureAccessibility() else {
            Task { await self.reportPermissionFailure() }
            return false
        }
        return true
    }

    // MARK: - Reporting

    private func reportPermissionFailure() async {
        let openSettings = await core.reportFailure(
            title: String(localized: "Tinycast Needs Accessibility Access"),
            message: String(localized: "Switching windows reads and raises other apps' windows."),
            symbol: "macwindow.on.rectangle", recovery: String(localized: "Open Settings"))
        if openSettings { Permissions.openAccessibilitySettings() }
    }

    private func reportGone(_ entry: WindowSwitchEntry) async {
        await core.showNotice(
            title: String(localized: "Couldn’t Switch to “\(entry.displayTitle)”"),
            message: String(localized: "It closed before the switch landed. Search again and retry."),
            symbol: "macwindow.on.rectangle", tone: .danger)
    }
}
