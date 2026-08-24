import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Borderless floating panel that hosts the SwiftUI command palette.
final class PalettePanel: NSPanel {
    /// Bare backspace, which the field editor swallows before `onKeyPress` could see it.
    var onBareBackspace: (() -> Bool)?
    /// Command chords the field editor swallows, plus the ones no main menu handles.
    var onCommandShortcut: ((NSEvent) -> Bool)?
    /// The palette's typing context, handed over each time a field takes focus.
    var onFieldEditorFocused: ((NSTextInputContext) -> Void)?
    /// Arms hover from `sendEvent`, the one place both event streams pass through.
    weak var paletteState: PaletteState? {
        didSet {
            paletteState?.onMenuOpenChanged = { [weak self] open in self?.setSearchCaretHidden(open) }
        }
    }

    /// Nil until a field takes focus; a non-activating panel can only scope input to this.
    var fieldEditorContext: NSTextInputContext? { fieldEditor?.inputContext }

    /// SwiftUI's text fields all edit through the window's one shared field editor.
    private var fieldEditor: NSTextView? { firstResponder as? NSTextView }

    /// Mirrors the field editor's marked text. docs/features/palette.md#ime-composition
    private var compositionObserver: NotificationToken?

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        guard super.makeFirstResponder(responder) else { return false }
        trackComposition()
        if let context = fieldEditorContext { onFieldEditorFocused?(context) }
        return true
    }

    /// Selection is the only notification a marked-text change posts; `didChange` waits for commit.
    func trackComposition() {
        guard let editor = fieldEditor else {
            compositionObserver = nil
            paletteState?.isComposing = false
            return
        }
        paletteState?.isComposing = editor.hasMarkedText()
        let center = NotificationCenter.default
        let token = center.addObserver(
            forName: NSTextView.didChangeSelectionNotification, object: editor, queue: .main
        ) { [weak self, weak editor] _ in
            MainActor.assumeIsolated {
                self?.paletteState?.isComposing = editor?.hasMarkedText() ?? false
            }
        }
        compositionObserver = NotificationToken(token, center: center)
    }

    /// ⌃N/⌃P/⌃F/⌃B respelled as their arrow, so the arrow handlers serve both spellings.
    private static func emacsArrow(for event: NSEvent) -> NSEvent? {
        guard event.modifierFlags.intersection([.command, .option, .control, .shift]) == .control
        else { return nil }
        let arrow: (key: KeyEquivalent, code: Int)
        // Character chords, not key codes: Dvorak transposes the two.
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "n": arrow = (.downArrow, kVK_DownArrow)
        case "p": arrow = (.upArrow, kVK_UpArrow)
        case "f": arrow = (.rightArrow, kVK_RightArrow)
        case "b": arrow = (.leftArrow, kVK_LeftArrow)
        default: return nil
        }
        let characters = String(arrow.key.character)
        return NSEvent.keyEvent(
            with: .keyDown,
            location: event.locationInWindow,
            modifierFlags: [.function, .numericPad],
            timestamp: event.timestamp,
            windowNumber: event.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: event.isARepeat,
            keyCode: UInt16(arrow.code))
    }

    /// Caret hiding on SwiftUI's own field editor. docs/features/palette.md#menu-open-input-freeze
    private func setSearchCaretHidden(_ hidden: Bool) {
        guard let editor = fieldEditor else { return }
        editor.insertionPointColor = hidden ? .clear : NSColor(Theme.Colors.textPrimary)
        // Force a redraw so the caret flips at once rather than waiting out the blink timer.
        editor.updateInsertionPointStateAndRestartTimer(!hidden)
    }

    /// Every event either mechanism sets a cursor on, so neither gets the last word.
    private static let cursorEvents: Set<NSEvent.EventType> = [
        .mouseMoved, .mouseEntered, .mouseExited, .cursorUpdate,
        .leftMouseDown, .leftMouseUp, .leftMouseDragged
    ]

    /// Two AppKit mechanisms disagree over the field — SwiftUI's clip view claims the arrow for
    /// the whole window as a cursor rect, the field editor claims the I-beam from its tracking
    /// area — so the panel settles it from the field's own frame, after `super` has had its say.
    private func applyCursorPolicy(for event: NSEvent) {
        guard Self.cursorEvents.contains(event.type) else { return }
        // Outset: the field editor AppKit installs is a point taller than the field it serves.
        let text = searchFieldRect.insetBy(dx: -Self.fieldEditorSlack, dy: -Self.fieldEditorSlack)
        let cursor: NSCursor =
            text.contains(convertPoint(fromScreen: NSEvent.mouseLocation)) ? .iBeam : .arrow
        guard NSCursor.current !== cursor else { return }
        cursor.set()
    }

    /// docs/features/palette.md: a 24pt editor in a 23pt field, so its I-beam overhangs.
    private static let fieldEditorSlack: CGFloat = 2

    /// SwiftUI reports the field top-left down; AppKit reads the window bottom-left up.
    private var searchFieldRect: CGRect {
        guard let frame = paletteState?.searchFieldFrame, !frame.isEmpty,
            let height = contentView?.bounds.height
        else { return .zero }
        return CGRect(
            x: frame.minX, y: height - frame.maxY, width: frame.width, height: frame.height)
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .mouseMoved: paletteState?.notePointerMoved(to: NSEvent.mouseLocation)
        // Keys and scrolling both slide rows under the pointer without it choosing any of them.
        case .keyDown, .scrollWheel:
            paletteState?.disarmHoverHighlight(pointerAt: NSEvent.mouseLocation)
        case .flagsChanged:
            paletteState?.noteCommandHeld(event.modifierFlags.contains(.command))
        default: break
        }
        defer { applyCursorPolicy(for: event) }
        // Before every other rule, so the arrows' own policies apply to the chords too.
        if event.type == .keyDown, let arrow = Self.emacsArrow(for: event) {
            sendEvent(arrow)
            return
        }
        // A footer menu owns the keyboard. See docs/features/palette.md#menu-open-input-freeze.
        if event.type == .keyDown,
            paletteState?.menuOpen == true,
            event.modifierFlags.isDisjoint(with: [.command, .control]),
            !MenuNavigation.handles(Int(event.keyCode))
        {
            return
        }
        if event.type == .keyDown,
            Int(event.keyCode) == kVK_Delete,
            event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]),
            onBareBackspace?() == true
        {
            return
        }
        // The controller owns the chords the field editor or a missing main menu would eat.
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
        // The controller owns the frame; without this the top edge drifts on the swap.
        hosting.sizingOptions = []
        contentView = hosting
    }

    /// Losing the keyboard is the last modifier news the panel gets; a re-show may skip `prepare`.
    override func resignKey() {
        super.resignKey()
        paletteState?.noteCommandHeld(false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
