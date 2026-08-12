import SwiftUI

/// Row icon decoding off the main thread; warm icons seed synchronously, so no flash.
struct AppIconView: View {
    let app: AppEntry
    @State private var image: NSImage?

    init(app: AppEntry) {
        self.app = app
        _image = State(initialValue: Self.cached(app))
    }

    /// Cache-only, so a warm icon paints on the same frame. An extension command is the one entry
    /// whose icon is neither its file's nor a plain symbol: a chosen appearance tints the tile, and
    /// otherwise it draws whatever image the extension ships.
    private static func cached(_ app: AppEntry) -> NSImage? {
        if app.isSymbolIcon {
            return IconCache.cachedSymbol(named: app.symbolIconName, tint: app.symbolTint)
        }
        if let path = app.imageIconPath { return IconCache.cachedImage(atPath: path) }
        return IconCache.cached(forFile: app.url.path)
    }

    private static func load(_ app: AppEntry) async -> NSImage? {
        if app.isSymbolIcon {
            return await IconCache.loadSymbolAsync(named: app.symbolIconName, tint: app.symbolTint)
        }
        if let path = app.imageIconPath { return await IconCache.loadImageAsync(atPath: path) }
        return await IconCache.loadAsync(forFile: app.url.path)
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
