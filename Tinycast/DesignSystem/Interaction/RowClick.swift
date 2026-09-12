import SwiftUI

/// Claims left-mouse events, so a row selects on the press and not a double-click interval later.
struct RowClickCatcher: NSViewRepresentable {
    let onSelect: () -> Void
    let onActivate: () -> Void

    func makeNSView(context: Context) -> NSView {
        CatcherView(onSelect: onSelect, onActivate: onActivate)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? CatcherView else { return }
        view.onSelect = onSelect
        view.onActivate = onActivate
    }

    private final class CatcherView: NSView {
        var onSelect: () -> Void
        var onActivate: () -> Void

        init(onSelect: @escaping () -> Void, onActivate: @escaping () -> Void) {
            self.onSelect = onSelect
            self.onActivate = onActivate
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func mouseDown(with event: NSEvent) {
            onSelect()
            guard event.clickCount == 2 else { return }
            onActivate()
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            switch NSApp.currentEvent?.type {
            case .leftMouseDown, .leftMouseUp, .leftMouseDragged:
                return super.hitTest(point)
            default:
                return nil
            }
        }
    }
}

extension View {
    func onRowClick(select: @escaping () -> Void, activate: @escaping () -> Void) -> some View {
        overlay(RowClickCatcher(onSelect: select, onActivate: activate))
    }
}
