import AppKit
import Carbon.HIToolbox

final class NotesPanel: NSPanel {
    var onHide: (() -> Void)?
    var onEscape: (() -> Void)?
    var onCreate: (() -> Void)?
    var onSearch: (() -> Void)?
    var onDelete: (() -> Void)?

    init(content: NSView) {
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Theme.Size.noteWidth,
                height: Theme.Size.noteMinimumHeight),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        hidesOnDeactivate = false
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
        isRestorable = false
        contentView = content
    }

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .keyDown, !event.isARepeat else {
            super.sendEvent(event)
            return
        }
        if Int(event.keyCode) == kVK_Escape {
            onEscape?()
            return
        }
        if event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "w": onHide?()
            case "n": onCreate?()
            case "p": onSearch?()
            default:
                if Int(event.keyCode) == kVK_Delete { onDelete?() } else {
                    super.sendEvent(event)
                }
            }
            return
        }
        super.sendEvent(event)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
