import AppKit
import SwiftUI

/// Drags a clipboard entry out as the file it already is, so an image reaches another app in one
/// gesture rather than through Reveal in Finder.
///
/// An overlay that tracks the gesture itself, like `WindowDragHandle`: the hosting view eats the
/// click first, and SwiftUI's `onDrag` hands over an `NSItemProvider` with no say in the operation
/// mask. That say is the point. Images live under `ClipboardStore.imagesDir` on the boot volume,
/// where a same-volume drop defaults to a **move** — which would carry the blob out of the history
/// and strand its row. An `NSDraggingSource` answers `.copy` and the entry stays.
struct ClipDragHandle: NSViewRepresentable {
    let url: URL
    var onSelect: () -> Void
    var onActivate: () -> Void
    var onDropped: () -> Void

    func makeNSView(context: Context) -> NSView { ClipDragView(url: url) }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? ClipDragView else { return }
        view.url = url
        view.bind(onSelect: onSelect, onActivate: onActivate, onDropped: onDropped)
    }
}

extension View {
    /// Marks a row as a drag source for `url`. A row without one keeps its SwiftUI gestures, so a
    /// text entry behaves exactly as before.
    func clipDraggable(
        _ url: URL?,
        onSelect: @escaping () -> Void,
        onActivate: @escaping () -> Void,
        onDropped: @escaping () -> Void
    ) -> some View {
        overlay {
            if let url {
                ClipDragHandle(
                    url: url, onSelect: onSelect, onActivate: onActivate, onDropped: onDropped)
            }
        }
    }
}

/// Claims mouse-down, then decides: past the slop it is a drag, otherwise it was the row's click.
private final class ClipDragView: NSView, NSDraggingSource {
    /// The slop AppKit itself allows before a press reads as a drag.
    private static let threshold: CGFloat = 4
    /// The row thumbnail is already cached at this size, so the preview costs no decode.
    private static let previewPixel: CGFloat = 64

    var url: URL
    private var onSelect: (() -> Void)?
    private var onActivate: (() -> Void)?
    private var onDropped: (() -> Void)?

    init(url: URL) {
        self.url = url
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func bind(
        onSelect: @escaping () -> Void, onActivate: @escaping () -> Void,
        onDropped: @escaping () -> Void
    ) {
        self.onSelect = onSelect
        self.onActivate = onActivate
        self.onDropped = onDropped
    }

    /// The row's own gestures never see this press, so the click they used to handle lands here.
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        // On the press, not the release: a drag that starts must carry the row it started on.
        onSelect?()
        if event.clickCount == 2 {
            onActivate?()
            return
        }
        // Deltas off `mouseLocation`, so no view or window coordinate conversion can drift.
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
        guard passedThreshold else { return }
        beginDrag(with: event)
    }

    /// `NSURL` writes the file URL every receiver understands, from Finder to a browser upload.
    private func beginDrag(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(bounds, contents: dragImage())
        beginDraggingSession(with: [item], event: event, source: self)
    }

    /// Cache-only lookups: a decode on mouse-down would stall the frame the drag begins on.
    private func dragImage() -> NSImage {
        ImageThumbnail.cached(url, maxPixel: Self.previewPixel)
            ?? FilePreviewThumbnail.cached(url, maxPixel: Self.previewPixel)
            ?? NSWorkspace.shared.icon(forFile: url.path)
    }

    // MARK: - NSDraggingSource

    /// Copy, always. The store owns the blob it hands out, and a move would delete it.
    func draggingSession(
        _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    /// A drop that landed is a finished errand, so the palette gets out of the way like a paste.
    func draggingSession(
        _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
    ) {
        guard operation != [] else { return }
        onDropped?()
    }
}
