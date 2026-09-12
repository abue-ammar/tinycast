import SwiftUI
import UniformTypeIdentifiers

/// The file, by whichever surface suits it. Shared by the preview pane and the ⌘Y overlay.
struct FileSearchFileView: View {
    let url: URL

    var body: some View {
        if FileSearchMediaPlayer.plays(url) {
            FileSearchMediaPlayer(url: url)
        } else if FileSearchTextPreview.reads(url) {
            FileSearchTextPreview(url: url)
        } else {
            QuickLookSurface(url: url)
        }
    }
}

/// Text is drawn here rather than by QuickLook, whose own scroll view carries a legacy scroller.
private struct FileSearchTextPreview: View {

    @Environment(\.metrics) private var metrics
    let url: URL
    @State private var text = ""

    /// Enough to read the head of a file; a log or a bundle dump is not a document to scroll.
    nonisolated private static let byteLimit = 128 * 1024

    static func reads(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .text) == true
    }

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(metrics.spacing.md)
        }
        .task(id: url) { text = await Self.read(url) }
    }

    nonisolated private static func read(_ url: URL) async -> String {
        await Task.detached(priority: .userInitiated) {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
            defer { try? handle.close() }
            let data = (try? handle.read(upToCount: byteLimit)) ?? Data()
            return String(decoding: data, as: UTF8.self)
        }.value
    }
}
