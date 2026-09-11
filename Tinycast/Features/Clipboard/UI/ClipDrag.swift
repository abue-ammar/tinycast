import AppKit
import SwiftUI

/// What a row hands to the app it is dropped on. The flavours are what receivers actually read:
/// a file URL for anything on disk, a URL *and* its text for a link, plain text for the rest.
enum ClipDragPayload: Equatable, Sendable {
    /// The stored blob for an image, the referenced file for a `.file` entry.
    case file(URL)
    /// A browser wants `public.url`, a text field wants the string. Writing both serves either.
    case link(URL, String)
    case text(String)

    /// A bare domain is still a link, and a browser rejects one without a scheme, so it gets
    /// `https://` — the same assumption the address bar makes.
    static func webURL(from text: String) -> URL? {
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }
        if token.contains("://") { return URL(string: token) }
        return URL(string: "https://" + token)
    }
}

/// Drags a clipboard entry out to another app, so reaching one costs a gesture rather than Reveal
/// in Finder or a paste into a scratch window.
///
/// An overlay that tracks the gesture itself, like `WindowDragHandle`: the hosting view eats the
/// click first, and SwiftUI's `onDrag` hands over an `NSItemProvider` with no say in the operation
/// mask. That say is the point. Images live under `ClipboardStore.imagesDir` on the boot volume,
/// where a same-volume drop defaults to a **move** — which would carry the blob out of the history
/// and strand its row. An `NSDraggingSource` answers `.copy` and the entry stays.
struct ClipDragHandle: NSViewRepresentable {
    let payload: ClipDragPayload
    var onSelect: () -> Void
    var onActivate: () -> Void
    var onDropped: () -> Void

    func makeNSView(context: Context) -> NSView { ClipDragView(payload: payload) }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? ClipDragView else { return }
        view.payload = payload
        view.bind(onSelect: onSelect, onActivate: onActivate, onDropped: onDropped)
    }
}

extension View {
    /// Marks a row as a drag source. The handle owns the press outright, so it takes the click and
    /// the double click the row's own gestures used to answer.
    func clipDraggable(
        _ payload: ClipDragPayload,
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

/// Claims mouse-down, then decides: past the slop it is a drag, otherwise it was the row's click.
private final class ClipDragView: NSView, NSDraggingSource {
    /// The slop AppKit itself allows before a press reads as a drag.
    private static let threshold: CGFloat = 4
    /// The row thumbnail is already cached at this size, so the fallback costs no decode.
    private static let previewPixel: CGFloat = 64

    var payload: ClipDragPayload
    private var onSelect: (() -> Void)?
    private var onActivate: (() -> Void)?
    private var onDropped: (() -> Void)?

    init(payload: ClipDragPayload) {
        self.payload = payload
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

    private func beginDrag(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: pasteboardWriter())
        item.setDraggingFrame(bounds, contents: dragImage())
        beginDraggingSession(with: [item], event: event, source: self)
    }

    /// `NSURL` writes the file URL every receiver understands, from Finder to a browser upload.
    /// A link writes two types from one item, so the receiver takes whichever it reads.
    private func pasteboardWriter() -> NSPasteboardWriting {
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

    /// The row as drawn, which is what SwiftUI's own drag preview shows and the only preview a text
    /// row can have. Converting into the superview keeps a container larger than the row honest.
    private func dragImage() -> NSImage? {
        guard let host = superview else { return fallbackImage() }
        let rect = convert(bounds, to: host)
        guard !rect.isEmpty, let rep = host.bitmapImageRepForCachingDisplay(in: rect) else {
            return fallbackImage()
        }
        host.cacheDisplay(in: rect, to: rep)
        let image = NSImage(size: rect.size)
        image.addRepresentation(rep)
        return image
    }

    /// Cache-only lookups: a decode on mouse-down would stall the frame the drag begins on.
    private func fallbackImage() -> NSImage? {
        guard case .file(let url) = payload else { return nil }
        return ImageThumbnail.cached(url, maxPixel: Self.previewPixel)
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
