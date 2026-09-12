import AppKit
import Carbon.HIToolbox

/// Keys go through `sendEvent`, so ↵, ⌘C and Esc need no focused subview to reach the panel.
final class QuickActionPanel: NSPanel {
    enum Key {
        case replace
        case copy
        case cancel
    }

    var onKey: ((Key) -> Void)?

    init(content: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: content.frame.size),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        // Above the palette, below a dialog: a failure report must still land on top of it.
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // Suppresses AppKit's own window animation; `fadeIn`/`fadeOut` replace it.
        animationBehavior = .none
        isReleasedWhenClosed = false
        isRestorable = false
        contentView = content
    }

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .keyDown, let onKey else {
            super.sendEvent(event)
            return
        }
        // ⌘C before the plain keys: the modifier is what separates Copy from anything else here.
        if event.modifierFlags.contains(.command) {
            guard Int(event.keyCode) == kVK_ANSI_C else {
                super.sendEvent(event)
                return
            }
            onKey(.copy)
            return
        }
        switch Int(event.keyCode) {
        case kVK_Escape:
            onKey(.cancel)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            onKey(.replace)
        default:
            super.sendEvent(event)
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
