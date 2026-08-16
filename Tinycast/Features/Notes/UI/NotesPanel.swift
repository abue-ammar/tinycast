import AppKit
import Carbon.HIToolbox

/// Both Notes windows. The editor and the switcher differ only in style mask and in the chords
/// their controller installs, so one non-activating floating panel serves the two of them.
final class NotesPanel: NSPanel {
    var onEscape: (() -> Void)?
    /// ⌘⌫ is keyed separately: only its key code survives every keyboard layout.
    var onDeleteChord: (() -> Bool)?
    /// The ⌘-letter chords this window claims, by lowercased character.
    var commandChords: [String: () -> Void] = [:]

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
        guard !event.isARepeat,
            event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command
        else { return false }
        if Int(event.keyCode) == kVK_Delete { return onDeleteChord?() == true }
        guard let key = event.charactersIgnoringModifiers?.lowercased(),
            let chord = commandChords[key]
        else { return false }
        chord()
        return true
    }

    override func sendEvent(_ event: NSEvent) {
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

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { acceptsMain }
}
