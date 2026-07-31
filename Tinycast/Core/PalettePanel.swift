import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Borderless floating panel that hosts the SwiftUI command palette.
final class PalettePanel: NSPanel {
    /// Called for a bare backspace before it reaches the field editor (return true to consume); the field editor swallows plain backspace itself, so SwiftUI `onKeyPress` up the hierarchy never sees it.
    var onBareBackspace: (() -> Bool)?
    /// Called for command-key chords before they reach the field editor; return true to consume the event. The field editor swallows some `⌘` chords (e.g. `⌘,`) before SwiftUI `.onKeyPress` can see them, and `LSUIElement` apps have no main menu to handle standard window equivalents like `⌘W`.
    var onCommandShortcut: ((NSEvent) -> Bool)?
    /// Arms the hover highlight from `sendEvent` — the one place both event streams pass through, so a keyboard-driven scroll under a still pointer never fires `.mouseMoved` and hover stays disarmed. Also carries the caret-hide hook fired when a footer menu opens.
    weak var paletteViewModel: PaletteViewModel? {
        didSet {
            paletteViewModel?.onMenuOpenChanged = { [weak self] open in self?.setSearchCaretHidden(open) }
        }
    }

    /// Keys that drive an open menu (navigate/activate/dismiss); they must reach SwiftUI's `onKeyPress` even while the menu freezes text editing.
    private static let menuNavKeys: Set<Int> = [
        kVK_UpArrow, kVK_DownArrow, kVK_LeftArrow, kVK_RightArrow,
        kVK_Return, kVK_ANSI_KeypadEnter, kVK_Escape, kVK_Tab
    ]

    /// Hide/show the caret on SwiftUI's *own* live field editor (the current first responder) without replacing it — SwiftUI force-casts the field editor to a private subclass, so vending our own crashes; we can only tune the existing one. The field never resigns first responder, so its text/placeholder never reflows.
    private func setSearchCaretHidden(_ hidden: Bool) {
        guard let editor = firstResponder as? NSTextView else { return }
        editor.insertionPointColor = hidden ? .clear : .white
        // Force an immediate redraw so the caret vanishes/returns on the menu toggle instead of waiting out the blink timer.
        editor.updateInsertionPointStateAndRestartTimer(!hidden)
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .mouseMoved: paletteViewModel?.hoverHighlightArmed = true
        case .keyDown: paletteViewModel?.hoverHighlightArmed = false
        default: break
        }
        // A footer menu owns the keyboard: the search field stays first responder (no focus swap, so nothing reflows) with only its caret hidden; swallow text-editing keystrokes before the field editor consumes them, but let shortcut chords (⌘K, ⌘⌫) and menu-nav keys reach SwiftUI's onKeyPress.
        if event.type == .keyDown,
            paletteViewModel?.menuOpen == true,
            event.modifierFlags.isDisjoint(with: [.command, .control]),
            !Self.menuNavKeys.contains(Int(event.keyCode)) {
            return
        }
        if event.type == .keyDown,
            Int(event.keyCode) == kVK_Delete,
            event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]),
            onBareBackspace?() == true {
            return
        }
        // The field editor swallows some command chords (e.g. `⌘,`) before SwiftUI `.onKeyPress` can fire, and `LSUIElement` apps have no main menu for standard equivalents like `⌘W`. Let the controller own those so the rest still reach SwiftUI.
        if event.type == .keyDown,
            event.modifierFlags.contains(.command),
            onCommandShortcut?(event) == true
        {
            return
        }
        super.sendEvent(event)
    }
    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 475),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        acceptsMouseMovedEvents = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: rootView)
        hosting.wantsLayer = true
        // The controller owns the frame: without this the hosting view resizes the panel to fit the SwiftUI content, dropping the top edge on the first compact→expanded mount.
        hosting.sizingOptions = []
        contentView = hosting
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
