import AppKit
import Carbon.HIToolbox

/// A camera surface's panel; keys go through `sendEvent`, so ↵ and Esc need no focused subview.
final class CameraPanel: NSPanel {
    enum Key {
        case primary
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
        // Above the palette, below a dialog: a confirmation must still land on top of it.
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
        switch Int(event.keyCode) {
        case kVK_Escape:
            onKey(.cancel)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            onKey(.primary)
        default:
            super.sendEvent(event)
        }
    }

    /// Control Center's video effects live in the menu bar, so a click there is not a click-away.
    static func pointerInMenuBar(at point: NSPoint = NSEvent.mouseLocation) -> Bool {
        NSScreen.screens.contains { screen in
            let bar = max(screen.frame.maxY - screen.visibleFrame.maxY, Self.autoHideStrip)
            return point.y >= screen.frame.maxY - bar
        }
    }

    /// What a menu bar falls back to once it auto-hides: `visibleFrame` stops reserving its strip.
    private static let autoHideStrip = NSStatusBar.system.thickness

    /// Optically centred on the screen under the cursor, the same lift a dialog takes.
    func centerOnCursorScreen() {
        guard let visible = NSScreen.underCursor?.visibleFrame else { return }
        let size = frame.size
        setFrameOrigin(
            NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2 + visible.height * Self.centerLift))
    }

    private static let centerLift: CGFloat = 0.08

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
