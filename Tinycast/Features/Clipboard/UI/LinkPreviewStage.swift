import SwiftUI

/// The preview pane's stage for a link entry: an Open Graph card beside the URL.
struct LinkPreviewStage: View {
    @Environment(\.metrics) private var metrics
    let text: String

    @State private var image: NSImage?
    @State private var isFetching: Bool

    private static func detectWebURL(_ text: String) -> URL? {
        guard case .web(let url) = QuicklinkDestination.detect(text),
            url.scheme == "http" || url.scheme == "https"
        else { return nil }
        return url
    }

    init(text: String) {
        self.text = text
        let url = Self.detectWebURL(text)
        if let url, let hit = LinkOGImageStore.cached(url, maxPixel: 900) {
            _image = State(initialValue: hit)
            _isFetching = State(initialValue: false)
        } else {
            _image = State(initialValue: nil)
            _isFetching = State(initialValue: true)
        }
    }

    private var webURL: URL? {
        Self.detectWebURL(text)
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    // Cap rather than fixed height so the pane never forces the panel taller.
                    .frame(maxHeight: metrics.size.clipboardMediaHeight)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
                            .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                    )
            } else if isFetching {
                ZStack {
                    RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
                        .fill(Theme.Colors.cardStroke.opacity(0.3))
                    Image(systemName: "link")
                        .font(.system(.title2))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 140)
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
                        .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                )
            }
        }
        .task(id: text) {
            guard let webURL else {
                image = nil
                isFetching = false
                return
            }
            if let hit = LinkOGImageStore.cached(webURL, maxPixel: metrics.size.clipboardPreviewPixel) {
                image = hit
                isFetching = false
                return
            }
            isFetching = true
            let result = await LinkOGImageStore.loadAsync(webURL, maxPixel: metrics.size.clipboardPreviewPixel)
            image = result.image
            isFetching = false
        }
    }
}
