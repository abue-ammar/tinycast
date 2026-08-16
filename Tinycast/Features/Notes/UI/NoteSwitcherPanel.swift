import AppKit
import Carbon.HIToolbox

/// The switcher's own window, so the list is not bounded by a note window that can be 180pt tall.
final class NoteSwitcherPanel: NSPanel {
    var onEscape: (() -> Void)?
    var onCreate: (() -> Void)?
    var onDelete: (() -> Bool)?

    init(content: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Theme.Size.noteSwitcher),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        hidesOnDeactivate = false
        // Above the note window it hangs from, and it travels with it as a child.
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

    /// The note window is not key while this is up, so its chords have to work here too.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        guard !event.isARepeat,
            event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command
        else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "n": onCreate?()
        case "w", "p": onEscape?()
        default:
            guard Int(event.keyCode) == kVK_Delete else { return false }
            return onDelete?() == true
        }
        return true
    }

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .keyDown, Int(event.keyCode) == kVK_Escape, !event.isARepeat else {
            super.sendEvent(event)
            return
        }
        // The search and rename fields own Escape while they are editing.
        if let fieldEditor = firstResponder as? NSTextView, fieldEditor.isFieldEditor {
            super.sendEvent(event)
            return
        }
        onEscape?()
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
