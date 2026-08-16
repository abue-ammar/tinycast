import AppKit
import SwiftUI

/// Hangs the switcher off the note window's action capsule as a child window, so it tracks every
/// move of its host and can still be taller than it.
@MainActor
final class NoteSwitcherWindowController: NSObject, NSWindowDelegate {
    private unowned let coordinator: NotesCoordinator
    private var panel: NoteSwitcherPanel?

    init(coordinator: NotesCoordinator) {
        self.coordinator = coordinator
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(under host: NSWindow) {
        let panel = ensurePanel()
        anchor(panel, under: host)
        if panel.parent !== host {
            panel.parent?.removeChildWindow(panel)
            host.addChildWindow(panel, ordered: .above)
        }
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
    }

    func hide() {
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    // MARK: - NSWindowDelegate

    /// A popover closes when the pointer goes elsewhere. The guard stops `hide()`'s own order-out
    /// from re-entering, and focus stays where the click landed rather than snapping to the editor.
    func windowDidResignKey(_ notification: Notification) {
        guard coordinator.isSwitcherPresented else { return }
        coordinator.closeSwitcher(focusEditor: false)
    }

    // MARK: - Private

    private func ensurePanel() -> NoteSwitcherPanel {
        if let panel { return panel }
        let root = NoteSwitcherView().environment(coordinator)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        let panel = NoteSwitcherPanel(content: hosting)
        panel.delegate = self
        panel.onEscape = { [weak coordinator] in coordinator?.closeSwitcher() }
        panel.onCreate = { [weak coordinator] in coordinator?.createNote() }
        panel.onDelete = { [weak coordinator] in coordinator?.handleDeleteShortcut() ?? false }
        self.panel = panel
        return panel
    }

    /// Trailing edges align with the capsule's, so it reads as hanging from the Browse button.
    private func anchor(_ panel: NoteSwitcherPanel, under host: NSWindow) {
        let size = Theme.Size.noteSwitcher
        let host = host.frame
        let origin = CGPoint(
            x: host.maxX - Theme.Spacing.md - size.width,
            y: host.maxY - Theme.Size.noteTitlebar - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
    }
}
