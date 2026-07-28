import AppKit
import ImageIO

/// Downsampled, memory-capped image loading for the clipboard UI: ImageIO decodes each on-disk image to exactly the pixel size needed and caches it in a system-evicted `NSCache`.
enum ImageThumbnail {
    /// `NSCache` is thread-safe but not annotated `Sendable`, so cross-thread use (a detached decode populating what the main actor reads) needs the guarantee asserted once here.
    private final class ImageCache: NSCache<NSString, NSImage>, @unchecked Sendable {}

    /// Small row thumbnails (≤ `rowThreshold` px), byte-bounded and kept warm across palette dismissals so re-opening draws instantly.
    private static let rowCache: ImageCache = {
        let cache = ImageCache()
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()

    /// Large previews (> `rowThreshold` px), byte-bounded (not object-count, which leaked) and purged on palette close so browsing memory stays flat.
    private static let previewCache: ImageCache = {
        let cache = ImageCache()
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    /// Longest-edge size at or below which a decode is a "row" thumbnail; larger is a "preview".
    private static let rowThreshold: CGFloat = 128

    private static func pick(_ maxPixel: CGFloat) -> NSCache<NSString, NSImage> {
        maxPixel <= rowThreshold ? rowCache : previewCache
    }

    private static func cacheKey(_ url: URL, _ maxPixel: CGFloat) -> NSString {
        "\(url.path)#\(Int(maxPixel))" as NSString
    }

    /// Frees the large preview bitmaps on palette dismiss; row thumbnails stay warm for an instant re-open.
    static func purgePreviews() {
        previewCache.removeAllObjects()
    }

    /// Cache-only lookup (never touches disk) so views render an already-decoded thumbnail on the same frame.
    static func cached(_ url: URL, maxPixel: CGFloat) -> NSImage? {
        pick(maxPixel).object(forKey: cacheKey(url, maxPixel))
    }

    /// Decodes off the main thread and reads the result back from the thread-safe cache; the `NSImage` never crosses the actor boundary, keeping it clean under strict concurrency.
    static func loadAsync(_ url: URL, maxPixel: CGFloat) async -> NSImage? {
        if let cached = cached(url, maxPixel: maxPixel) { return cached }
        await Task.detached(priority: .userInitiated) {
            _ = load(url, maxPixel: maxPixel)
        }.value
        return cached(url, maxPixel: maxPixel)
    }

    /// A thumbnail no larger than `maxPixel` on its longest edge, cached per (path, size); decodes synchronously, so call off the main thread for anything user-facing.
    static func load(_ url: URL, maxPixel: CGFloat) -> NSImage? {
        let cache = pick(maxPixel)
        let key = cacheKey(url, maxPixel)
        if let cached = cache.object(forKey: key) { return cached }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        let image = NSImage(
            cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        // Cost = the decoded bitmap's real byte footprint, so `totalCostLimit` bounds actual RAM.
        cache.setObject(image, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }

    /// Pixel dimensions read from image metadata — no full decode.
    static func pixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = props[kCGImagePropertyPixelWidth] as? Int,
            let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return CGSize(width: width, height: height)
    }
}
