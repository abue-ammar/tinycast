import AppKit
import SwiftUI

@MainActor
final class PaletteState {
    var menuOpen = false { didSet { onMenuOpenChanged?(menuOpen) } }
    var onMenuOpenChanged: ((Bool) -> Void)?
    var isComposing = false
    var searchFieldFrame = CGRect.zero

    func notePointerMoved(to: CGPoint) {}
    func disarmHoverHighlight(pointerAt: CGPoint) {}
    func noteCommandHeld(_ held: Bool) {}
}

@MainActor
enum ASCIIKeyboardLayout {
    static func character(for event: NSEvent) -> String? { nil }
}

@MainActor
private final class PressView: NSView {
    var received: [NSEvent.EventType] = []
    var activations = 0
    private var pressed = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        received.append(event.type)
        pressed = true
    }

    override func mouseUp(with event: NSEvent) {
        received.append(event.type)
        if pressed { activations += 1 }
        pressed = false
    }

    override func mouseDragged(with event: NSEvent) { received.append(event.type) }
    override func rightMouseDown(with event: NSEvent) { received.append(event.type) }
    override func rightMouseUp(with event: NSEvent) { received.append(event.type) }
    override func rightMouseDragged(with event: NSEvent) { received.append(event.type) }
}

@main
@MainActor
struct PaletteMenuClickTests {
    private static var failures = 0

    private static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        _ = NSApplication.shared
        let state = PaletteState()
        let panel = PalettePanel(rootView: Color.clear)
        panel.paletteState = state
        let view = PressView(frame: panel.contentView?.bounds ?? .zero)
        panel.contentView = view
        panel.setFrameOrigin(CGPoint(x: -10000, y: -10000))
        panel.orderFront(nil)
        panel.becomeKey()
        panel.displayIfNeeded()
        defer { panel.orderOut(nil) }

        func send(_ type: NSEvent.EventType, clicks: Int = 1) {
            guard
                let event = NSEvent.mouseEvent(
                    with: type, location: CGPoint(x: 50, y: 50), modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                    context: nil, eventNumber: 1, clickCount: clicks, pressure: 1)
            else {
                check(false, "mouse event creation")
                return
            }
            panel.sendEvent(event)
        }

        var dismissals = 0
        func openMenu() {
            state.menuOpen = true
            panel.onDismissMenu = { [weak panel, weak state] in
                dismissals += 1
                state?.menuOpen = false
                panel?.onDismissMenu = nil
            }
            view.received.removeAll()
        }

        send(.leftMouseDown)
        send(.leftMouseUp)
        check(view.activations == 1, "an ordinary click reaches its control")

        openMenu()
        send(.leftMouseDown)
        check(dismissals == 1 && !state.menuOpen, "the press dismisses immediately")
        send(.leftMouseDragged)
        send(.leftMouseUp)
        check(view.received.isEmpty, "the entire dismissal press stays out of the content view")
        check(view.activations == 1, "a dismissing click cannot activate the underlying control")

        send(.leftMouseDown, clicks: 2)
        send(.leftMouseUp, clicks: 2)
        check(view.received == [.leftMouseDown, .leftMouseUp], "the next double-click pair arrives intact")
        check(view.activations == 2, "the next click activates exactly once")

        openMenu()
        send(.rightMouseDown)
        send(.rightMouseDragged)
        send(.rightMouseUp)
        check(dismissals == 2, "right-click dismisses once")
        check(view.received.isEmpty, "right-click dismissal cannot open an underlying row menu")

        send(.rightMouseDown)
        send(.rightMouseUp)
        check(view.received == [.rightMouseDown, .rightMouseUp], "an ordinary right-click still arrives")

        openMenu()
        send(.leftMouseDown)
        send(.leftMouseDown, clicks: 2)
        send(.leftMouseUp, clicks: 2)
        check(view.received == [.leftMouseDown, .leftMouseUp], "a missed release cannot eat the next press")
        check(view.activations == 3, "the next press works even if dismissal released outside the window")

        print("Palette menu click tests: \(failures) failure(s)")
        exit(failures == 0 ? 0 : 1)
    }
}
