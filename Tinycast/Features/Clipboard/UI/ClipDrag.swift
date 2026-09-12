import AppKit
import SwiftUI

/// AppKit, not `onDrag`: only an `NSDraggingSource` can force `.copy` over a same-volume move.
struct ClipDragHandle: NSViewRepresentable {
    /// Read when the drag starts, not when the row draws: resolving it stats the file.
    var payload: () -> ClipDragPayload?
    var onSelect: () -> Void
    var onActivate: () -> Void
    var onDropped: () -> Void

    func makeNSView(context: Context) -> NSView { ClipDragView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ClipDragView)?
            .bind(payload: payload, onSelect: onSelect, onActivate: onActivate, onDropped: onDropped)
    }
}

extension View {
    /// The handle owns the press, so a tap gesture underneath never sees click or double click.
    func clipDraggable(
        payload: @escaping () -> ClipDragPayload?,
        onSelect: @escaping () -> Void,
        onActivate: @escaping () -> Void,
        onDropped: @escaping () -> Void
    ) -> some View {
        overlay {
            ClipDragHandle(
                payload: payload, onSelect: onSelect, onActivate: onActivate, onDropped: onDropped)
        }
    }
}

private final class ClipDragView: NSView, NSDraggingSource {
    private static let threshold: CGFloat = 4
    /// The row tile is already cached at this size, so the preview costs no decode.
    private static let previewPixel: CGFloat = 64

    private var payload: (() -> ClipDragPayload?)?
    private var onSelect: (() -> Void)?
    private var onActivate: (() -> Void)?
    private var onDropped: (() -> Void)?

    func bind(
        payload: @escaping () -> ClipDragPayload?, onSelect: @escaping () -> Void,
        onActivate: @escaping () -> Void, onDropped: @escaping () -> Void
    ) {
        self.payload = payload
        self.onSelect = onSelect
        self.onActivate = onActivate
        self.onDropped = onDropped
    }

    /// Left button only, so the row's right-click catcher underneath still opens the actions menu.
    override func hitTest(_ point: NSPoint) -> NSView? {
        switch NSApp.currentEvent?.type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged: return nil
        default: return super.hitTest(point)
        }
    }

    /// Tracks the gesture itself, like `WindowDragHandle`: the hosting view eats the click first.
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        onSelect?()
        if event.clickCount == 2 {
            onActivate?()
            return
        }
        // Deltas off `mouseLocation`, so no coordinate conversion can drift.
        let start = NSEvent.mouseLocation
        var passedThreshold = false
        window.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration,
            mode: .eventTracking
        ) { tracked, stop in
            guard let tracked, tracked.type != .leftMouseUp else {
                stop.pointee = true
                return
            }
            let mouse = NSEvent.mouseLocation
            guard hypot(mouse.x - start.x, mouse.y - start.y) > Self.threshold else { return }
            passedThreshold = true
            stop.pointee = true
        }
        guard passedThreshold, let payload = payload?() else { return }
        beginDrag(payload, with: event)
    }

    private func beginDrag(_ payload: ClipDragPayload, with event: NSEvent) {
        let image = dragImage(for: payload)
        let item = NSDraggingItem(pasteboardWriter: pasteboardWriter(for: payload))
        // Sized to the image and centred on the cursor. The row's shape would stretch a thumbnail.
        let origin = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(
            NSRect(
                x: origin.x - image.size.width / 2, y: origin.y - image.size.height / 2,
                width: image.size.width, height: image.size.height),
            contents: image)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        // A refused drop flies back, so a drag that achieved nothing says so.
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    /// A link writes two types from one item, so the receiver takes whichever it reads.
    private func pasteboardWriter(for payload: ClipDragPayload) -> NSPasteboardWriting {
        switch payload {
        case .file(let url):
            return url as NSURL
        case .link(let url, let text):
            let item = NSPasteboardItem()
            item.setString(url.absoluteString, forType: .URL)
            item.setString(text, forType: .string)
            return item
        case .text(let text):
            return text as NSString
        }
    }

    /// Drawn, not snapshotted: SwiftUI draws into layers, so `cacheDisplay` returns a clear bitmap.
    private func dragImage(for payload: ClipDragPayload) -> NSImage {
        switch payload {
        case .file(let url):
            // Cache-only: a decode on mouse-down stalls the frame the drag begins on.
            return ImageThumbnail.cached(url, maxPixel: Self.previewPixel)
                ?? FilePreviewThumbnail.cached(url, maxPixel: Self.previewPixel)
                ?? NSWorkspace.shared.icon(forFile: url.path)
        case .link(_, let text), .text(let text):
            return Self.textImage(text)
        }
    }

    private static func textImage(_ copy: String) -> NSImage {
        let line = copy.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        let string = NSAttributedString(
            string: String(line.prefix(60)),
            attributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor
            ])
        let inset = NSSize(width: 10, height: 6)
        let text = string.size()
        let size = NSSize(
            width: min(text.width, 320) + inset.width * 2, height: text.height + inset.height * 2)
        return NSImage(size: size, flipped: false) { rect in
            NSColor.controlBackgroundColor.withAlphaComponent(0.95).setFill()
            NSBezierPath(
                roundedRect: rect, xRadius: Theme.Radius.thumbnail, yRadius: Theme.Radius.thumbnail
            ).fill()
            string.draw(
                in: NSRect(
                    x: inset.width, y: inset.height, width: rect.width - inset.width * 2,
                    height: text.height))
            return true
        }
    }

    // MARK: - NSDraggingSource

    /// Copy, always: the store owns the blob it hands out, and a move would delete it.
    func draggingSession(
        _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(
        _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
    ) {
        guard operation != [] else { return }
        onDropped?()
    }
}
