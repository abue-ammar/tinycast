import SwiftUI

/// Right-click handler used as an `.overlay` whose `hitTest` claims only right-mouse events (left-clicks pass through), so the actions popover can anchor to a fixed point instead of the cursor.
struct RightClickCatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView { CatcherView(action: action) }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? CatcherView)?.action = action
    }

    private final class CatcherView: NSView {
        var action: () -> Void
        init(action: @escaping () -> Void) {
            self.action = action
            super.init(frame: .zero)
        }
        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func rightMouseDown(with event: NSEvent) { action() }

        override func hitTest(_ point: NSPoint) -> NSView? {
            switch NSApp.currentEvent?.type {
            case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
                return super.hitTest(point)
            default:
                return nil
            }
        }
    }
}

/// Location-reporting variant for grid containers: one catcher serves every cell, delivering the click point in top-left (SwiftUI-local) coordinates for hit-testing math.
struct RightClickLocationCatcher: NSViewRepresentable {
    let action: (CGPoint) -> Void

    func makeNSView(context: Context) -> NSView { CatcherView(action: action) }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? CatcherView)?.action = action
    }

    private final class CatcherView: NSView {
        var action: (CGPoint) -> Void
        init(action: @escaping (CGPoint) -> Void) {
            self.action = action
            super.init(frame: .zero)
        }
        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        // Flipped so the reported point matches SwiftUI's top-left local coordinate space.
        override var isFlipped: Bool { true }

        override func rightMouseDown(with event: NSEvent) {
            action(convert(event.locationInWindow, from: nil))
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            switch NSApp.currentEvent?.type {
            case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
                return super.hitTest(point)
            default:
                return nil
            }
        }
    }
}

extension View {
    func onRightClick(perform action: @escaping () -> Void) -> some View {
        overlay(RightClickCatcher(action: action))
    }

    func onRightClick(perform action: @escaping (CGPoint) -> Void) -> some View {
        overlay(RightClickLocationCatcher(action: action))
    }
}
