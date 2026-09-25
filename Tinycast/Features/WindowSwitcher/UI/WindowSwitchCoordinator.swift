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
        // Pressed again while open, the shortcut steps down the list rather than closing it.
        if paletteCoordinator.isShowing(.switchWindows) { return step() }
        paletteCoordinator.togglePalette(mode: .switchWindows)
    }

    /// The first step lands on the window behind the current one, which the list opens on.
    private func step() {
        let count = session.filtered.count
        guard count > 0 else { return }
        palette.selection = (palette.selection + 1) % count
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

    private func switchOnRelease() {
        if let releaseMonitor { NSEvent.removeMonitor(releaseMonitor) }
        releaseMonitor = nil
        let rows = session.filtered
        guard paletteCoordinator.isShowing(.switchWindows), rows.indices.contains(palette.selection)
        else { return }
        activate(rows[palette.selection])
    }

    /// Every open sweeps anew, a restore included: hiding dropped the last snapshot.
    func load() {
        guard Permissions.ensureAccessibility() else {
            Task { await self.reportPermissionFailure() }
            return
        }
        session.present(WindowSwitchSweep.snapshot(ranks: WindowZOrder.appRanks()))
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
        AXWindowAccess.focus(element.window, in: element.application, of: element.app)
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
