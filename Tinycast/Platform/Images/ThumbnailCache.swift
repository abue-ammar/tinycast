import AppKit

/// Unchecked: its whole state is two `let` `NSCache`s, thread-safe in themselves.
final class ThumbnailCache: @unchecked Sendable {
    private final class Cache: NSCache<NSString, NSImage> {}

    /// Longest-edge size at or below which a bitmap is a row tile; larger is a preview.
    private static let rowThreshold: CGFloat = 128

    private let rows = Cache()
    private let previews = Cache()

    init(rowBytes: Int, previewBytes: Int) {
        rows.totalCostLimit = rowBytes
        previews.totalCostLimit = previewBytes
    }

    private func tier(_ maxPixel: CGFloat) -> Cache {
        maxPixel <= Self.rowThreshold ? rows : previews
    }

    private func key(_ url: URL, _ maxPixel: CGFloat) -> NSString {
        "\(url.path)#\(Int(maxPixel))" as NSString
    }

    func cached(_ url: URL, maxPixel: CGFloat) -> NSImage? {
        tier(maxPixel).object(forKey: key(url, maxPixel))
    }

    /// Cost is the decoded bitmap's real footprint, so a limit bounds actual RAM.
    func store(_ image: NSImage, for url: URL, maxPixel: CGFloat, cost: Int) {
        tier(maxPixel).setObject(image, forKey: key(url, maxPixel), cost: cost)
    }

    /// Frees the large bitmaps on dismiss; row tiles stay warm for a re-open.
    func purgePreviews() {
        previews.removeAllObjects()
    }
}
