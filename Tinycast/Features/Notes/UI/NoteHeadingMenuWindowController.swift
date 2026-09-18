import AppKit
import SwiftUI

/// A child window, so the menu can outgrow a short note window; it never takes key from the editor.
@MainActor
final class NoteHeadingMenuWindowController {
    private unowned let coordinator: NotesCoordinator
    private var panel: NotesPanel?

    init(coordinator: NotesCoordinator) {
        self.coordinator = coordinator
    }

    func show(above host: NSWindow) {
        let panel = ensurePanel()
        anchor(panel, above: host)
        if panel.parent !== host {
            panel.parent?.removeChildWindow(panel)
            host.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
        panel.invalidateShadow()
    }

    func hide() {
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    private func ensurePanel() -> NotesPanel {
        if let panel { return panel }
        let hosting = NSHostingView(rootView: NoteHeadingMenuView().environment(coordinator))
        hosting.sizingOptions = []
        let panel = NotesPanel(
            content: hosting,
            size: Theme.Size.noteHeadingMenu,
            styleMask: .borderless,
            acceptsMain: false)
        panel.acceptsKey = false
        self.panel = panel
        return panel
    }

    /// Hangs off the heading button itself, whose frame arrives flipped from the SwiftUI bar.
    private func anchor(_ panel: NotesPanel, above host: NSWindow) {
        let button = coordinator.headingButtonFrame
        let origin = CGPoint(
            x: host.frame.minX + button.minX,
            y: host.frame.maxY - button.minY + Theme.Spacing.xs)
        panel.setFrame(NSRect(origin: origin, size: Theme.Size.noteHeadingMenu), display: false)
    }
}
