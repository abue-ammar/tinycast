import AppKit

/// The one funnel from a palette row or a global hotkey to the mover.
@MainActor
final class WindowCommandCoordinator {
    private let settings: AppSettings
    private let paletteCoordinator: PaletteCoordinator
    private let windowMover: WindowMover
    private let workspaceStore: WindowWorkspaceStore
    private let spaceSwitcher: SpaceSwitcher
    private let showMessage: (String) -> Void

    init(
        settings: AppSettings, paletteCoordinator: PaletteCoordinator, windowMover: WindowMover,
        workspaceStore: WindowWorkspaceStore, spaceSwitcher: SpaceSwitcher,
        showMessage: @escaping (String) -> Void
    ) {
        self.settings = settings
        self.paletteCoordinator = paletteCoordinator
        self.windowMover = windowMover
        self.workspaceStore = workspaceStore
        self.spaceSwitcher = spaceSwitcher
        self.showMessage = showMessage
    }

    /// The one funnel for palette and hotkey alike. See docs/features/window-management.md#wiring.
    func runWindowCommand(id: WindowCommand.ID) {
        guard settings.windowManagementEnabled else { return }
        if id == .restoreWorkspace {
            if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
            restoreSelectedWorkspace()
            return
        }
        if let direction = SpaceDirection(id) {
            // Restoring focus reactivates an app elsewhere, pulling its Space forward.
            if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
            spaceSwitcher.perform(direction)
            return
        }
        let target = paletteCoordinator.targetApp
        if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: true) }
        windowMover.perform(
            id, target: target, gap: CGFloat(settings.windowGap),
            cycleOnRepeat: settings.windowCycleOnRepeat)
    }

    func saveWorkspace(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let windows = windowMover.captureWorkspace()
        guard !windows.isEmpty else {
            showMessage("No accessible windows to save")
            return
        }
        workspaceStore.save(name: trimmed, windows: windows)
        showMessage("Saved \(trimmed)")
    }

    func restoreSelectedWorkspace() {
        guard let workspace = workspaceStore.selected else {
            showMessage("Choose a workspace in Settings first")
            return
        }
        let restored = windowMover.restoreWorkspace(workspace)
        showMessage(
            restored == 0 ? "Opened available apps for \(workspace.name)" : "Restored \(workspace.name)")
    }
}
