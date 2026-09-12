import SwiftUI

/// Row icon decoding off the main thread; warm icons seed synchronously, so no flash.
struct AppIconView: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.displayScale) private var displayScale
    let app: AppEntry
    var pointSize: CGFloat?
    @State private var loaded: Loaded?

    private struct Key: Hashable {
        let icon: String
        let size: IconSize?
    }

    private struct Loaded {
        let request: IconRequest<Key>
        let image: NSImage?
    }

    var body: some View {
        let size = pointSize.map { IconSize(points: $0, scale: displayScale) }
        let request = IconRequest(Key(icon: app.iconKey, size: size))
        let warm = IconCache.cached(app.iconSource, fileURL: app.url, size: size)
        let image = warm ?? (loaded?.request == request ? loaded?.image : nil)
        Group {
            if let image {
                Image(nsImage: image).resizable()
            } else {
                RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                    .fill(Theme.Colors.iconPlaceholder)
            }
        }
        .task(id: request) {
            if let warm {
                loaded = Loaded(request: request, image: warm)
                return
            }
            loaded = nil
            let image = await IconCache.loadAsync(app.iconSource, fileURL: app.url, size: size)
            guard !Task.isCancelled else { return }
            loaded = Loaded(request: request, image: image)
        }
    }
}
