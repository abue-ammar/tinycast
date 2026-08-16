import SwiftUI

/// A window-drag handle that treats a stationary mouse-up as a click, so the title can both move
/// the panel and open the switcher.
struct ClickableDragHandle: NSViewRepresentable {
    var onClick: () -> Void
    var onEnded: () -> Void

    func makeNSView(context: Context) -> NSView { ClickableDragView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ClickableDragView)?.bind(onClick: onClick, onEnded: onEnded)
    }
}

extension View {
    /// Marks a region as a drag-or-click window handle; an overlay, so it wins the hit-test race.
    func clickableDraggable(
        onClick: @escaping () -> Void,
        onEnded: @escaping () -> Void
    ) -> some View {
        overlay {
            ClickableDragHandle(onClick: onClick, onEnded: onEnded)
                .accessibilityHidden(true)
        }
    }
}

/// Tracks the drag itself rather than calling `performDrag(with:)`, which hands the gesture to the
/// window server and returns at once — leaving no way to know when the mouse actually comes up.
private class ClickableDragView: NSView {
    private static let clickDragThreshold: CGFloat = 3

    private var onClick: (() -> Void)?
    private var onEnded: (() -> Void)?

    func bind(onClick: @escaping () -> Void, onEnded: @escaping () -> Void) {
        self.onClick = onClick
        self.onEnded = onEnded
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        // Snapshotted at gesture start, so a SwiftUI update mid-drag can't swap the callbacks.
        let clicked = onClick
        let ended = onEnded
        // Deltas off `mouseLocation`, so no view or window coordinate conversion can drift.
        let origin = window.frame.origin
        let start = NSEvent.mouseLocation
        var isDragging = false
        window.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration,
            mode: .eventTracking
        ) { tracked, stop in
            guard let tracked, tracked.type != .leftMouseUp else {
                stop.pointee = true
                return
            }
            let mouse = NSEvent.mouseLocation
            if !isDragging {
                let distance = hypot(mouse.x - start.x, mouse.y - start.y)
                guard distance >= Self.clickDragThreshold else { return }
                isDragging = true
            }
            window.setFrameOrigin(
                CGPoint(x: origin.x + mouse.x - start.x, y: origin.y + mouse.y - start.y))
        }
        if isDragging {
            ended?()
        } else {
            clicked?()
        }
    }
}
