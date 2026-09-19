import AppKit

/// The one funnel from a palette row or a global hotkey to the mover.
@MainActor
final class WindowCommandCoordinator {
    private let settings: AppSettings
    private let paletteCoordinator: PaletteCoordinator
    private let windowMover: WindowMover
    private let spaceSwitcher: SpaceSwitcher
    private let customSizes: CustomWindowSizeStore

    init(
        settings: AppSettings, paletteCoordinator: PaletteCoordinator, windowMover: WindowMover,
        spaceSwitcher: SpaceSwitcher, customSizes: CustomWindowSizeStore
    ) {
        self.settings = settings
        self.paletteCoordinator = paletteCoordinator
        self.windowMover = windowMover
        self.spaceSwitcher = spaceSwitcher
        self.customSizes = customSizes
    }

    /// The one funnel for palette and hotkey alike. See docs/features/window-management.md#wiring.
    func runWindowCommand(id: WindowCommand.ID) {
        guard settings.windowManagementEnabled else { return }
        if let direction = SpaceDirection(id) {
            // Restoring focus reactivates an app elsewhere, pulling its Space forward.
            if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
            spaceSwitcher.perform(direction)
            return
        }
        windowMover.perform(
            id, target: handOffTarget(), gap: CGFloat(settings.windowGap),
            cycle: settings.windowCycle)
    }

    /// The same funnel for a custom size, so the feature switch gates it identically.
    func runCustomWindowSize(id: UUID) {
        guard settings.windowManagementEnabled, let size = customSizes.size(id: id) else { return }
        windowMover.perform(size, target: handOffTarget(), gap: CGFloat(settings.windowGap))
    }

    /// The window to place, read before the palette hides and hands focus back to it.
    private func handOffTarget() -> WindowTarget? {
        guard paletteCoordinator.isVisible else { return WindowTarget.current() }
        let target = WindowTarget.behindPalette(
            ownWindow: paletteCoordinator.previousOwnWindow, app: paletteCoordinator.targetApp)
        paletteCoordinator.hidePalette(restoreFocus: true)
        return target
    }
}
