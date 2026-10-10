import AppKit
import SwiftUI

@MainActor
final class PaletteState {
    var menuOpen = false { didSet { onMenuOpenChanged?(menuOpen) } }
    var onMenuOpenChanged: ((Bool) -> Void)?
    var isComposing = false
    var searchFieldFrame = CGRect.zero
    var mode = PaletteMode.launcher

    func notePointerMoved(to: CGPoint) {}
    func disarmHoverHighlight(pointerAt: CGPoint) {}
    func noteCommandHeld(_ held: Bool) {}
}

enum PaletteMode {
    case launcher, quicklinkEditor
    var isNativeEditor: Bool { self == .quicklinkEditor }
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

        if let scroll = CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -40, wheel2: 0, wheel3: 0),
            let event = NSEvent(cgEvent: scroll)
        {
            openMenu()
            panel.sendEvent(event)
            check(state.menuOpen, "scrolling other screens preserves their menu policy")
            state.mode = .quicklinkEditor
            panel.sendEvent(event)
            check(
                !state.menuOpen && dismissals == 4,
                "scrolling a native form dismisses its menu before the anchor moves")
        } else {
            check(false, "scroll event creation")
        }

        let field = NSTextField(frame: NSRect(x: 80, y: 100, width: 250, height: 32))
        view.addSubview(field)
        let textArea = NSTextView(frame: NSRect(x: 80, y: 160, width: 250, height: 78))
        view.addSubview(textArea)
        for mode: PaletteMode in [.launcher, .quicklinkEditor] {
            state.mode = mode
            check(
                panel.cursor(at: NSPoint(x: 100, y: 116)) === NSCursor.iBeam,
                "editable fields use the text cursor independently of the screen")
            check(
                panel.cursor(at: NSPoint(x: 100, y: 180)) === NSCursor.iBeam,
                "textareas use the text cursor independently of the screen")
            check(
                panel.cursor(at: NSPoint(x: 50, y: 50)) === NSCursor.arrow,
                "bare content retains the arrow")
        }
        field.isEditable = false
        textArea.isEditable = false
        check(
            panel.cursor(at: NSPoint(x: 100, y: 116)) === NSCursor.arrow,
            "noneditable text fields retain the arrow")
        check(
            panel.cursor(at: NSPoint(x: 100, y: 180)) === NSCursor.arrow,
            "noneditable text views retain the arrow")
        state.mode = .launcher
        state.searchFieldFrame = CGRect(x: 350, y: 40, width: 250, height: 23)
        check(
            panel.cursor(at: NSPoint(x: 400, y: view.bounds.height - 50)) === NSCursor.iBeam,
            "the search rectangle still supplies its stable cursor")

        let hosting = NSHostingView(
            rootView: ScrollView {
                TextField("Extension placeholder", text: .constant(""))
                    .textFieldStyle(.plain)
                    .frame(width: 360, height: 32)
                    .padding(20)
            })
        panel.contentView = hosting
        panel.displayIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        if let field = textField(in: hosting) {
            let rect = field.convert(field.bounds, to: nil)
            let point = NSPoint(x: rect.midX, y: rect.midY)
            state.searchFieldFrame = .zero
            check(
                panel.cursor(at: point) === NSCursor.iBeam,
                "a SwiftUI text field receives the text cursor through its native rectangle")
            field.isHidden = true
            check(panel.cursor(at: point) === NSCursor.arrow, "hidden fields never claim the cursor")
        } else {
            check(false, "SwiftUI mounts its native text field")
        }

        print("Palette menu click tests: \(failures) failure(s)")
        exit(failures == 0 ? 0 : 1)
    }

    private static func textField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField { return field }
        return view.subviews.lazy.compactMap { textField(in: $0) }.first
    }
}
