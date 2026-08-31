import SwiftUI

/// Row icon decoding off the main thread; warm icons seed synchronously, so no flash.
struct AppIconView: View {
    let app: AppEntry
    @State private var image: NSImage?

    init(app: AppEntry) {
        self.app = app
        _image = State(initialValue: Self.cached(app))
    }

    /// Cache-only, so a warm icon paints on the same frame; the kind is `iconSource`'s answer.
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
                    .fill(Theme.Colors.iconPlaceholder)
            }
        }
        // Keyed on the icon, not the entry: re-skinning an extension leaves `id` untouched.
        .task(id: IconRequest(app.iconKey)) {
            if let warm = Self.cached(app) {
                image = warm
                return
            }
            image = await Self.load(app)
        }
    }
}
