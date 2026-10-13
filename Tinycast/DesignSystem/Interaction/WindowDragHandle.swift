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

/// A background, so only empty space drags; `performDrag(with:)` lets the window pick what moves.
struct WindowDragBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { BackgroundDragView() }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class BackgroundDragView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

struct EmptyFieldDragHandle: NSViewRepresentable {
    var isEmpty: Bool
    var onBegan: () -> Void
    var onEnded: () -> Void
    var onClick: () -> Void

    func makeNSView(context: Context) -> NSView { EmptyFieldDragView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? EmptyFieldDragView else { return }
        view.isEmpty = isEmpty
        view.bind(onBegan: onBegan, onEnded: onEnded, onClick: onClick)
    }
}

/// Tracks the drag itself: `performDrag(with:)` returns at once, never saying when the mouse rose.
private class DragView: NSView {
    private var onBegan: (() -> Void)?
    private var onEnded: (() -> Void)?
    private var onClick: (() -> Void)?
    /// Slop before a press is a drag, so a click that never moves stays a click.
    private static let dragSlop: CGFloat = 3

    func bind(
        onBegan: @escaping () -> Void, onEnded: @escaping () -> Void,
        onClick: (() -> Void)? = nil
    ) {
        self.onBegan = onBegan
        self.onEnded = onEnded
        self.onClick = onClick
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        // Deltas off `mouseLocation`, so no view or window coordinate conversion can drift.
        let origin = window.frame.origin
        let start = NSEvent.mouseLocation
        var dragging = false
        window.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration,
            mode: .eventTracking
        ) { tracked, stop in
            guard let tracked, tracked.type != .leftMouseUp else {
                stop.pointee = true
                return
            }
            let mouse = NSEvent.mouseLocation
            guard dragging || hypot(mouse.x - start.x, mouse.y - start.y) > Self.dragSlop else {
                return
            }
            if !dragging {
                dragging = true
                self.onBegan?()
            }
            window.setFrameOrigin(
                CGPoint(x: origin.x + mouse.x - start.x, y: origin.y + mouse.y - start.y))
        }
        // A press that never moved was a click on whatever the handle covers, not a drag.
        if dragging { onEnded?() } else { onClick?() }
    }
}

/// Steps out of the way rather than measuring the text: a caret or a selection is never a drag.
private final class EmptyFieldDragView: DragView {
    var isEmpty = true

    override func hitTest(_ point: NSPoint) -> NSView? { isEmpty ? super.hitTest(point) : nil }
}
