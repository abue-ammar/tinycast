import SwiftUI

/// Draws an `EntryIcon`, seeded from the cache so a warm glyph paints on the first frame.
struct EntryIconView: View {
    let source: EntryIcon
    /// Only `.file` needs it, and only the launcher has one to give.
    var fileURL: URL = URL(fileURLWithPath: "/")
    @State private var image: NSImage?

    init(source: EntryIcon, fileURL: URL = URL(fileURLWithPath: "/")) {
        self.source = source
        self.fileURL = fileURL
        _image = State(initialValue: IconCache.cached(source, fileURL: fileURL))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable()
            } else {
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            }
        }
        // Keyed on the glyph, not the entry: re-skinning leaves an id untouched.
        .task(id: source) {
            if let warm = IconCache.cached(source, fileURL: fileURL) {
                image = warm
                return
            }
            image = await IconCache.loadAsync(source, fileURL: fileURL)
        }
    }
}
