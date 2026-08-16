import SwiftUI

/// Row icon decoding off the main thread; warm icons seed synchronously, so no flash.
struct AppIconView: View {
    let app: AppEntry
    @State private var image: NSImage?

    init(app: AppEntry) {
        self.app = app
        _image = State(initialValue: Self.cached(app))
    }

    /// Cache-only, so a warm icon paints on the same frame. Which of the four kinds of glyph an entry
    /// wants is `iconSource`'s answer, not this view's.
    private static func cached(_ app: AppEntry) -> NSImage? {
        IconCache.cached(app.iconSource, fileURL: app.url)
    }

    private static func load(_ app: AppEntry) async -> NSImage? {
        await IconCache.loadAsync(app.iconSource, fileURL: app.url)
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
        // Keyed on the icon, not the entry: re-skinning an extension leaves `id` untouched.
        .task(id: app.iconKey) {
            if let warm = Self.cached(app) {
                image = warm
                return
            }
            image = await Self.load(app)
        }
    }
}
