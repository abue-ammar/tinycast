import SwiftUI

struct FileSearchSurface: View {
    let url: URL
    @State private var sniffed: Sniffed?

    /// The head of a file whose extension left its kind open, read once per selection.
    private struct Sniffed: Sendable {
        let url: URL
        let kind: FileSearchPreviewKind
        let text: String?
    }

    /// Enough of a source file to read, and a bound on what a binary costs to rule out.
    private nonisolated static let headLimit = 256 * 1024

    var body: some View {
        surface.task(id: url) { await sniff() }
    }

    @ViewBuilder private var surface: some View {
        let sniffed = self.sniffed?.url == url ? self.sniffed : nil
        switch FileSearchPreviewKind(pathExtension: url.pathExtension) ?? sniffed?.kind {
        case .quickLook: QuickLookSurface(url: url)
        case .pdf: PDFSurface(url: url)
        case .media: FileSearchMediaPlayer(url: url)
        case .text: PlainTextSurface(text: sniffed?.text ?? "")
        case nil: Color.clear
        }
    }

    private func sniff() async {
        guard FileSearchPreviewKind(pathExtension: url.pathExtension) == nil else { return }
        let url = url
        let read = await Task.detached(priority: .userInitiated) { Self.readHead(of: url) }.value
        // Cancelling the selection does not stop the read, so a late one must not land on the next.
        guard !Task.isCancelled else { return }
        sniffed = read
    }

    private nonisolated static func readHead(of url: URL) -> Sniffed {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return Sniffed(url: url, kind: .quickLook, text: nil)
        }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: headLimit)) ?? Data()
        let kind = FileSearchPreviewKind(
            pathExtension: url.pathExtension, head: head, isWholeFile: head.count < headLimit)
        let text = kind == .text ? String(decoding: head, as: UTF8.self) : nil
        return Sniffed(url: url, kind: kind, text: text)
    }
}
