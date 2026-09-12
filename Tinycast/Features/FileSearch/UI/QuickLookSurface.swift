import QuickLookUI
import SwiftUI

/// A live QuickLook view of one file: the document itself, scrollable and playable as it comes.
struct QuickLookSurface: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        // Arrow-keying a list must not start a movie, and the panel outlives any one preview.
        view.autostarts = false
        view.shouldCloseWithWindow = false
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        guard view.previewItem as? URL != url else { return }
        view.previewItem = url as NSURL
    }

    /// The preview holds its decoder open until it is closed, and this is the last chance.
    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        view.close()
    }
}
