import AppKit
import QuickLookThumbnailing

/// Content thumbnails for any file type — a video's poster frame, a PDF's page, else its icon.
enum FilePreviewThumbnailer {
    /// `NSCache` is thread-safe but not `Sendable`, so assert the guarantee once here.
    private final class ImageCache: NSCache<NSString, NSImage>, @unchecked Sendable {}

    /// Row tiles, byte-bounded and kept warm, so re-opening the clipboard draws instantly.
    private static let rowCache: ImageCache = {
        let cache = ImageCache()
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()

    /// Large previews, byte-bounded and purged on close, so browsing memory stays flat.
    private static let previewCache: ImageCache = {
        let cache = ImageCache()
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    /// Longest-edge size at or below which a render is a "row" tile; larger is a "preview".
    private static let rowThreshold: CGFloat = 128

    private static func pick(_ maxPixel: CGFloat) -> NSCache<NSString, NSImage> {
        maxPixel <= rowThreshold ? rowCache : previewCache
    }

    private static func cacheKey(_ url: URL, _ maxPixel: CGFloat) -> NSString {
        "\(url.path)#\(Int(maxPixel))" as NSString
    }

    /// Frees the preview bitmaps on dismiss; row tiles stay warm for a re-open.
    static func purgePreviews() {
        previewCache.removeAllObjects()
    }

    /// Cache-only, never touching disk, so a warm tile renders on the same frame.
    static func cached(_ url: URL, maxPixel: CGFloat) -> NSImage? {
        pick(maxPixel).object(forKey: cacheKey(url, maxPixel))
    }

    /// Returns the render directly, so an eviction mid-flight can't strand a placeholder.
    static func loadAsync(_ url: URL, maxPixel: CGFloat) async -> NSImage? {
        if let cached = cached(url, maxPixel: maxPixel) { return cached }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: maxPixel, height: maxPixel), scale: 2,
            representationTypes: .all)
        let rendered = try? await QLThumbnailGenerator.shared.generateBestRepresentation(
            for: request)
        guard let cgImage = rendered?.cgImage else { return nil }
        let image = NSImage(
            cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        // Cost = the decoded bitmap's real byte footprint, so `totalCostLimit` bounds actual RAM.
        pick(maxPixel).setObject(
            image, forKey: cacheKey(url, maxPixel), cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }
}
