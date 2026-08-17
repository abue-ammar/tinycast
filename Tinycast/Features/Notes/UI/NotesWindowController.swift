import AppKit
import SwiftUI

@MainActor
final class NotesWindowController: NSObject, NSWindowDelegate {
    private static let frameAutosaveName = "Notes Window"

    private unowned let coordinator: NotesCoordinator
    private var panel: NotesPanel?
    private weak var editor: NoteTextView?
    private var previousApp: NSRunningApplication?
    private weak var previousOwnWindow: NSWindow?

    init(coordinator: NotesCoordinator) {
        self.coordinator = coordinator
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(focusEditor: Bool) {
        let panel = ensurePanel()
        if !panel.isVisible { captureFocusTarget() }
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        seatTrafficLights(in: panel)
        // The corner is clipped in SwiftUI, so the shadow has to be recut from what was drawn.
        panel.invalidateShadow()
        if focusEditor { self.focusEditor(in: panel) }
    }

    func hide(restoreFocus: Bool) {
        let restore = restoreFocus && !userMovedOn
        panel?.orderOut(nil)
        guard restore else { return }
        if let previousOwnWindow, previousOwnWindow.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            previousOwnWindow.makeKeyAndOrderFront(nil)
        } else {
            previousApp?.activate()
        }
    }

    func editorReady(_ textView: NoteTextView) {
        editor = textView
        guard let panel, panel.isVisible else { return }
        focusEditor(in: panel)
    }

    func focusEditor() {
        guard let panel, panel.isVisible else { return }
        focusEditor(in: panel)
    }

    /// Only this controller knows the host window, so handing it over stays its job.
    func presentSwitcher(_ switcher: NoteSwitcherWindowController) {
        guard let panel, panel.isVisible else { return }
        switcher.show(under: panel)
    }

    // MARK: - NSWindowDelegate

    /// The red button and ⌘W both arrive here, so closing is one path and never destroys state.
    func windowWillClose(_ notification: Notification) {
        coordinator.hide()
    }

    /// `contentMinSize` alone leaks frames below it; AppKit takes whatever this returns verbatim.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(
            width: max(frameSize.width, Theme.Size.noteWindow.width),
            height: max(frameSize.height, Theme.Size.noteWindow.height))
    }

    func windowDidResize(_ notification: Notification) {
        guard let panel else { return }
        seatTrafficLights(in: panel)
    }

    // MARK: - Private

    private func ensurePanel() -> NotesPanel {
        if let panel { return panel }
        let root = NotesView().environment(coordinator)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        let panel = NotesPanel(
            content: hosting,
            size: Theme.Size.noteWindow,
            styleMask: [.titled, .closable, .resizable],
            acceptsMain: true)
        // A title-bar accessory drops AppKit off its centred-title layout, so `NotesView` draws it.
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        // `.automatic` draws a hairline the moment the editor scrolls under the bar.
        panel.titlebarSeparatorStyle = .none
        panel.contentMinSize = Theme.Size.noteWindow
        panel.delegate = self
        panel.onEscape = { [weak coordinator] in coordinator?.handleEscape() }
        panel.onDeleteChord = { [weak coordinator] in coordinator?.handleDeleteShortcut() ?? false }
        panel.commandChords = [
            "n": { [weak coordinator] in coordinator?.createNote() },
            "p": { [weak coordinator] in coordinator?.searchNotes() },
            "o": { [weak coordinator] in coordinator?.openNotesFolder() },
            "w": { [weak panel] in panel?.performClose(nil) }
        ]
        panel.setFrameAutosaveName(Self.frameAutosaveName)
        if !panel.setFrameUsingName(Self.frameAutosaveName) { panel.center() }
        // An autosaved frame can sit below the floor, so it is clamped on the way back in.
        panel.setContentSize(
            CGSize(
                width: max(panel.frame.width, Theme.Size.noteWindow.width),
                height: max(panel.frame.height, Theme.Size.noteWindow.height)))
        self.panel = panel
        observeTitle()
        return panel
    }

    /// Idempotent, because AppKit re-seats the lights on a resize and on every title assignment.
    private func seatTrafficLights(in window: NSWindow) {
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap(window.standardWindowButton)
        guard let leading = buttons.first, let band = leading.superview?.bounds.height else {
            return
        }
        // Centred in the drawn band, not AppKit's shorter one, and clamped so none is clipped.
        let size = leading.frame.height
        let y = max(0, band - size - (Theme.Size.noteTitlebar - size) / 2)
        let shift = Theme.Size.noteTrafficLightInset - leading.frame.minX
        guard shift != 0 || leading.frame.origin.y != y else { return }
        for button in buttons {
            button.frame.origin.x += shift
            button.frame.origin.y = y
        }
    }

    /// Re-armed after every read, so a rename reaches the title without waiting for the next show.
    private func observeTitle() {
        withObservationTracking {
            panel?.title = coordinator.activeTitle
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observeTitle()
                if let panel = self.panel { self.seatTrafficLights(in: panel) }
            }
        }
    }

    private var userMovedOn: Bool {
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return frontmost != NSRunningApplication.current.processIdentifier
            && frontmost != previousApp?.processIdentifier
    }

    private func captureFocusTarget() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier == NSRunningApplication.current.processIdentifier {
            previousApp = nil
            if let keyWindow = NSApp.keyWindow, keyWindow !== panel {
                previousOwnWindow = keyWindow
            }
        } else {
            previousApp = frontmost
            previousOwnWindow = nil
        }
    }

    private func focusEditor(in panel: NotesPanel) {
        guard let editor else { return }
        panel.makeFirstResponder(editor)
        Task { @MainActor [weak panel, weak editor] in
            await Task.yield()
            guard let panel, panel.isVisible, let editor else { return }
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(editor)
        }
    }
}
