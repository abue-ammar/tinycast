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

    /// Aligned to the bar's capsule, whose top sits half a capsule above the band's centre.
    private func anchor(_ panel: NotesPanel, above host: NSWindow) {
        let capsuleHeight = Theme.Size.barButtonHeight + Theme.Spacing.xs * 2
        let capsuleTop = (Theme.Size.bottomBarHeight + capsuleHeight) / 2
        let origin = CGPoint(
            x: host.frame.minX + Theme.Spacing.md,
            y: host.frame.minY + capsuleTop + Theme.Spacing.xs)
        panel.setFrame(NSRect(origin: origin, size: Theme.Size.noteHeadingMenu), display: false)
    }
}
