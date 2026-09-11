import AppKit
import QuickLookUI

@MainActor
final class FileQuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = FileQuickLookController()

    private var previewURL: URL?

    var isVisible: Bool {
        QLPreviewPanel.shared()?.isVisible == true
    }

    func toggle(url: URL) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible, previewURL == url {
            close()
            return
        }
        show(url: url)
    }

    func show(url: URL) {
        previewURL = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.floatingWindow)) + 1)
        panel.reloadData()
        if !panel.isVisible {
            panel.orderFront(nil)
        }
    }

    func updateIfVisible(url: URL) {
        guard isVisible, previewURL != url else { return }
        previewURL = url
        QLPreviewPanel.shared()?.reloadData()
    }

    func close() {
        previewURL = nil
        guard let panel = QLPreviewPanel.shared(), panel.isVisible else { return }
        panel.orderOut(nil)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        previewURL = nil
    }

    // MARK: - QLPreviewPanelDataSource

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated {
            previewURL != nil ? 1 : 0
        }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        let url = MainActor.assumeIsolated {
            previewURL
        }
        return url.map { $0 as NSURL }
    }
}
