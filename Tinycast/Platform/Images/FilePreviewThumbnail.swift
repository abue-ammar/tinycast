import AppKit
import QuickLookThumbnailing

/// Content thumbnails for any file type — a poster frame, a PDF's page, else the type's icon.
enum FilePreviewThumbnail {
    private static let cache = ThumbnailCache(
        rowBytes: 8 * 1024 * 1024, previewBytes: 32 * 1024 * 1024)

    /// Cache-only, never touching disk, so a warm tile renders on the same frame.
    static func cached(_ url: URL, maxPixel: CGFloat) -> NSImage? {
        cache.cached(url, maxPixel: maxPixel)
    }

    static func purgePreviews() {
        cache.purgePreviews()
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
        cache.store(
            image, for: url, maxPixel: maxPixel, cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }
}
