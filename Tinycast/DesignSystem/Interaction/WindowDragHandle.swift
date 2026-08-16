import SwiftUI

/// Starts a window drag on mouse-down — the hosting view otherwise eats the click first.
struct WindowDragHandle: NSViewRepresentable {
    var onBegan: () -> Void
    var onEnded: () -> Void

    func makeNSView(context: Context) -> NSView { DragView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? DragView)?.bind(onBegan: onBegan, onEnded: onEnded)
    }
}

extension View {
    /// Marks a region as a window-drag handle; an overlay, so it wins the hit-test race.
    func windowDraggable(
        _ enabled: Bool,
        onBegan: @escaping () -> Void = {},
        onEnded: @escaping () -> Void = {}
    ) -> some View {
        overlay {
            if enabled { WindowDragHandle(onBegan: onBegan, onEnded: onEnded) }
        }
    }
}

/// Drags past the visible text; declines over it, so a click there edits/selects normally.
struct TextTrailingDragHandle: NSViewRepresentable {
    var text: String
    var font: NSFont
    var onBegan: () -> Void
    var onEnded: () -> Void

    func makeNSView(context: Context) -> NSView { TextTailDragView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? TextTailDragView else { return }
        view.text = text
        view.font = font
        view.bind(onBegan: onBegan, onEnded: onEnded)
    }
}

/// Tracks the drag itself rather than calling `performDrag(with:)`, which hands the gesture to the
/// window server and returns at once — leaving no way to know when the mouse actually comes up.
private class DragView: NSView {
    private var onBegan: (() -> Void)?
    private var onEnded: (() -> Void)?

    func bind(onBegan: @escaping () -> Void, onEnded: @escaping () -> Void) {
        self.onBegan = onBegan
        self.onEnded = onEnded
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        // Deltas off `mouseLocation`, so no view or window coordinate conversion can drift.
        let origin = window.frame.origin
        let start = NSEvent.mouseLocation
        onBegan?()
        window.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration,
            mode: .eventTracking
        ) { tracked, stop in
            guard let tracked, tracked.type != .leftMouseUp else {
                stop.pointee = true
                return
            }
            let mouse = NSEvent.mouseLocation
            window.setFrameOrigin(
                CGPoint(x: origin.x + mouse.x - start.x, y: origin.y + mouse.y - start.y))
        }
        onEnded?()
    }
}

/// Claims only the run of the field past its text, measured in the font the field draws with.
private final class TextTailDragView: DragView {
    var text = ""
    var font: NSFont = .systemFont(ofSize: NSFont.systemFontSize)
    /// Slack so a click right at the text's trailing edge still edits rather than drags.
    private static let edgeSlack: CGFloat = 4

    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` is in the superview's coordinates; the text is measured from our own leading edge.
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        return local.x > textWidth + Self.edgeSlack ? super.hitTest(point) : nil
    }
}
