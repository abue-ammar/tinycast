import SwiftUI

struct RowDragItem {
    let writer: any NSPasteboardWriting
    let image: NSImage

    /// `image` is the row's warm tile: a decode on mouse-down stalls the frame the drag begins on.
    static func file(_ url: URL, image: NSImage?) -> RowDragItem {
        RowDragItem(writer: url as NSURL, image: image ?? NSWorkspace.shared.icon(forFile: url.path))
    }
}

/// A row another app can take. Copy only, so a user's file, an app or an owned blob never moves.
struct RowDrag {
    /// Read when the drag starts, not when the row draws; nil refuses the drag.
    let item: () -> RowDragItem?
    /// A landed drop only; a refused one flies back to the row, so a drag that did nothing says so.
    let dropped: () -> Void
}

extension View {
    /// Selects on the press rather than a double-click interval later; a double click activates.
    func onRowClick(
        select: @escaping () -> Void, activate: @escaping () -> Void, drag: RowDrag? = nil
    ) -> some View {
        overlay(
            RowPressCatcher(activation: .doubleClick, select: select, activate: activate, drag: drag))
    }

    /// A tap that can drag out: activation waits for the release, so a drag never activates.
    @ViewBuilder
    func onRowTap(drag: RowDrag?, perform activate: @escaping () -> Void) -> some View {
        if let drag {
            overlay(RowPressCatcher(activation: .release, select: {}, activate: activate, drag: drag))
        } else {
            onTapGesture(perform: activate)
        }
    }
}

/// AppKit, not `onDrag`: only an `NSDraggingSource` can force `.copy` over a same-volume move.
private struct RowPressCatcher: NSViewRepresentable {
    let activation: RowPressView.Activation
    let select: () -> Void
    let activate: () -> Void
    let drag: RowDrag?

    func makeNSView(context: Context) -> RowPressView { RowPressView() }

    func updateNSView(_ view: RowPressView, context: Context) {
        view.activation = activation
        view.select = select
        view.activate = activate
        view.drag = drag
    }
}

/// Owns the whole left press, because the hosting view otherwise eats the click first.
private final class RowPressView: NSView, NSDraggingSource {
    enum Activation {
        /// On the press of a double click: a list beside a preview selects with a single one.
        case doubleClick
        /// On a single click's release, which is the moment a press is known not to be a drag.
        case release
    }

    private static let dragSlop: CGFloat = 4

    var activation = Activation.doubleClick
    var select: () -> Void = {}
    var activate: () -> Void = {}
    var drag: RowDrag?

    /// Left button only, so the row's right-click catcher still opens the actions menu.
    override func hitTest(_ point: NSPoint) -> NSView? {
        switch NSApp.currentEvent?.type {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged:
            return super.hitTest(point)
        default:
            return nil
        }
    }

    override func mouseDown(with event: NSEvent) {
        select()
        if activation == .doubleClick {
            guard event.clickCount < 2 else {
                activate()
                return
            }
            guard drag != nil else { return }
        }
        guard pressBecomesDrag() else {
            if activation == .release { activate() }
            return
        }
        guard let item = drag?.item() else { return }
        beginDrag(item, with: event)
    }

    /// Tracks the press itself, like `WindowDragHandle`, until it is released or leaves the slop.
    private func pressBecomesDrag() -> Bool {
        guard let window else { return false }
        // Deltas off `mouseLocation`, so no coordinate conversion can drift.
        let start = NSEvent.mouseLocation
        var passedSlop = false
        window.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration,
            mode: .eventTracking
        ) { tracked, stop in
            guard let tracked, tracked.type != .leftMouseUp else {
                stop.pointee = true
                return
            }
            let mouse = NSEvent.mouseLocation
            guard hypot(mouse.x - start.x, mouse.y - start.y) > Self.dragSlop else { return }
            passedSlop = true
            stop.pointee = true
        }
        return passedSlop
    }

    private func beginDrag(_ item: RowDragItem, with event: NSEvent) {
        let image = item.image
        let dragging = NSDraggingItem(pasteboardWriter: item.writer)
        // Sized to the image and centred on the cursor. The row's shape would stretch a thumbnail.
        let origin = convert(event.locationInWindow, from: nil)
        dragging.setDraggingFrame(
            NSRect(
                x: origin.x - image.size.width / 2, y: origin.y - image.size.height / 2,
                width: image.size.width, height: image.size.height),
            contents: image)
        let session = beginDraggingSession(with: [dragging], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    // MARK: - NSDraggingSource

    func draggingSession(
        _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(
        _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
    ) {
        guard operation != [] else { return }
        drag?.dropped()
    }
}
