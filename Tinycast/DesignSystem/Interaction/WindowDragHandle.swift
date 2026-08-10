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
    /// Marks a region as a window-drag handle; an overlay, so it wins the hit-test race.
    func windowDraggable() -> some View {
        overlay(WindowDragHandle())
    }
}

/// Drags past the visible text; declines over it, so a click there edits/selects normally.
struct TextTrailingDragHandle: NSViewRepresentable {
    var text: String
    var font: NSFont

    func makeNSView(context: Context) -> CatcherView { CatcherView() }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.text = text
        nsView.font = font
    }

    final class CatcherView: NSView {
        var text = ""
        var font: NSFont = .systemFont(ofSize: NSFont.systemFontSize)
        /// Slack so a click right at the text's trailing edge still edits rather than drags.
        private static let edgeSlack: CGFloat = 4

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard bounds.contains(point) else { return nil }
            let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
            return point.x > textWidth + Self.edgeSlack ? self : nil
        }
    }
}
