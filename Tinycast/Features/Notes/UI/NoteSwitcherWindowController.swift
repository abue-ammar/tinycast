import AppKit
import SwiftUI

/// A child window of the note panel, so it tracks its host's every move and can still outgrow it.
@MainActor
final class NoteSwitcherWindowController: NSObject, NSWindowDelegate {
    private unowned let coordinator: NotesCoordinator
    private var panel: NotesPanel?

    init(coordinator: NotesCoordinator) {
        self.coordinator = coordinator
    }

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

    /// Closes like a popover; focus stays where the click landed rather than snapping to the editor.
    func windowDidResignKey(_ notification: Notification) {
        guard coordinator.isSwitcherPresented else { return }
        coordinator.closeSwitcher(focusEditor: false)
    }

    // MARK: - Private

    private func ensurePanel() -> NotesPanel {
        if let panel { return panel }
        let root = NoteSwitcherView().environment(coordinator)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        let panel = NotesPanel(
            content: hosting,
            size: Theme.Size.noteSwitcher,
            styleMask: .borderless,
            acceptsMain: false)
        panel.delegate = self
        let dismiss: () -> Void = { [weak coordinator] in coordinator?.closeSwitcher() }
        panel.onEscape = dismiss
        panel.onDeleteChord = { [weak coordinator] in coordinator?.handleDeleteShortcut() ?? false }
        // The note window is not key while this is up, so its dismissal chords have to work here.
        panel.commandChords = [
            "n": { [weak coordinator] in coordinator?.createNote() },
            "w": dismiss,
            "p": dismiss
        ]
        self.panel = panel
        return panel
    }

    /// Trailing edges align with the capsule's, so it reads as hanging from the Browse button.
    private func anchor(_ panel: NotesPanel, under host: NSWindow) {
        let size = Theme.Size.noteSwitcher
        let host = host.frame
        let origin = CGPoint(
            x: host.maxX - Theme.Spacing.md - size.width,
            y: host.maxY - Theme.Size.noteTitlebar - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
    }
}
