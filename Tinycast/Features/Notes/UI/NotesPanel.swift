import AppKit
import Carbon.HIToolbox

/// Editor and switcher differ only in style mask and chords, so one panel serves both.
final class NotesPanel: NSPanel {
    var onEscape: (() -> Void)?
    /// ⌘⌫ is keyed separately: only its key code survives every keyboard layout.
    var onDeleteChord: (() -> Bool)?
    /// The ⌘-letter chords this window claims, by lowercased character.
    var commandChords: [String: () -> Void] = [:]
    /// The same, for ⌥⌘-letter chords.
    var optionCommandChords: [String: () -> Void] = [:]
    /// False for the heading menu, so the editor keeps its caret, reveal and chords beneath it.
    var acceptsKey = true
    var onMouseDown: (() -> Void)?

    private let acceptsMain: Bool

    init(content: NSView, size: CGSize, styleMask: NSWindow.StyleMask, acceptsMain: Bool) {
        self.acceptsMain = acceptsMain
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: styleMask.union([.fullSizeContentView, .nonactivatingPanel]),
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        hidesOnDeactivate = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        isReleasedWhenClosed = false
        isRestorable = false
        contentView = content
    }

    /// The main menu is offered chords first, so this is the fallback for a non-activating panel.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        guard !event.isARepeat else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased()
        if modifiers == [.command, .option] {
            guard let key, let chord = optionCommandChords[key] else { return false }
            chord()
            return true
        }
        guard modifiers == .command else { return false }
        if Int(event.keyCode) == kVK_Delete { return onDeleteChord?() == true }
        guard let key, let chord = commandChords[key] else { return false }
        chord()
        return true
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown { onMouseDown?() }
        // The search and rename fields own Escape while they are editing.
        guard event.type == .keyDown, Int(event.keyCode) == kVK_Escape, !event.isARepeat,
            (firstResponder as? NSTextView)?.isFieldEditor != true
        else {
            super.sendEvent(event)
            return
        }
        onEscape?()
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override var canBecomeKey: Bool { acceptsKey }
    override var canBecomeMain: Bool { acceptsMain }
}
