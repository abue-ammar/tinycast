import AppKit
import Carbon.HIToolbox

/// A camera surface's panel; keys go through `sendEvent`, so ↵ and Esc need no focused subview.
final class CameraPanel: NSPanel {
    enum Action {
        case primary
        case cancel
    }

    var onAction: ((Action) -> Void)?
    private var clickMonitors: [Any] = []

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
        guard event.type == .keyDown, let onAction else {
            super.sendEvent(event)
            return
        }
        switch Int(event.keyCode) {
        case kVK_Escape:
            onAction(.cancel)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            onAction(.primary)
        default:
            super.sendEvent(event)
        }
    }

    override func becomeKey() {
        super.becomeKey()
        stopWatchingClicks()
    }

    /// Losing key is a click away, unless system UI took it: a menu-bar reframe keeps the feed.
    override func resignKey() {
        super.resignKey()
        guard let onAction else { return }
        if Self.systemUIIsUnderPointer { watchForClickAway() } else { onAction(.cancel) }
    }

    override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        stopWatchingClicks()
    }

    /// With key already gone, a click away raises no further `resignKey`; only a monitor sees it.
    private func watchForClickAway() {
        guard clickMonitors.isEmpty else { return }
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let otherApps = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            self?.clickedAway()
        }
        // The global monitor never sees this app's own windows.
        let thisApp = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
            if event.window !== self { self?.clickedAway() }
            return event
        }
        clickMonitors = [otherApps, thisApp].compactMap { $0 }
    }

    private func clickedAway() {
        guard !Self.systemUIIsUnderPointer else { return }
        stopWatchingClicks()
        onAction?(.cancel)
    }

    private func stopWatchingClicks() {
        clickMonitors.forEach(NSEvent.removeMonitor)
        clickMonitors = []
    }

    /// The menu bar, everything it drops down and the Dock all sit at or above the Dock's level.
    private static var systemUIIsUnderPointer: Bool {
        let pointer = NSEvent.mouseLocation
        let number = NSWindow.windowNumber(at: pointer, belowWindowWithWindowNumber: 0)
        guard number > 0,
            let info = CGWindowListCopyWindowInfo(
                [.optionOnScreenAboveWindow, .optionIncludingWindow], CGWindowID(number))
                as? [[String: Any]],
            let window = info.first(where: { ($0[kCGWindowNumber as String] as? Int) == number }),
            let layer = window[kCGWindowLayer as String] as? Int
        else { return false }
        return layer >= Int(CGWindowLevelForKey(.dockWindow))
    }

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
