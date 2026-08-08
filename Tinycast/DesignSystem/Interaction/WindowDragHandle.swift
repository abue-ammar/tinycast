import SwiftUI

/// Starts a window drag on mouse-down — the hosting view otherwise eats the click first.
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

extension View {
    /// Marks a region as a drag handle for a borderless, title-bar-less window.
    func windowDraggable() -> some View {
        background(WindowDragHandle())
    }
}
