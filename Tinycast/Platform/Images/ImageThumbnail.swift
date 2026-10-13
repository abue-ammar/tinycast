import AppKit
import ImageIO

enum ImageThumbnail {
    private static let cache = ThumbnailCache(
        rowBytes: 8 * 1024 * 1024, previewBytes: 8 * 1024 * 1024)

    /// Frees the preview bitmaps on dismiss; row thumbnails stay warm for a re-open.
    static func purgePreviews() {
        cache.purgePreviews()
    }

    /// Cache-only, never touching disk, so a warm thumbnail renders on the same frame.
    static func cached(_ url: URL, maxPixel: CGFloat) -> NSImage? {
        cache.cached(url, maxPixel: maxPixel)
    }

    /// A freshly-decoded, thereafter-immutable `NSImage` is safe to move across the actor boundary.
    private struct Decoded: @unchecked Sendable { let image: NSImage? }

    /// Returns the decode directly, so an eviction mid-decode can't strand a placeholder.
    static func loadAsync(_ url: URL, maxPixel: CGFloat, derived: Bool = false) async -> NSImage? {
        if let cached = cached(url, maxPixel: maxPixel) { return cached }
        return await Task.detached(priority: .userInitiated) {
            Decoded(image: load(url, maxPixel: maxPixel, derived: derived))
        }.value.image
    }

    static func load(_ url: URL, maxPixel: CGFloat, derived: Bool = false) -> NSImage? {
        if let cached = cached(url, maxPixel: maxPixel) { return cached }

        let decodable = derived ? derivative(of: url, maxPixel: maxPixel) ?? url : url
        guard let cgImage = downsample(decodable, maxPixel: maxPixel) else { return nil }

        let image = NSImage(
            cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.store(
            image, for: url, maxPixel: maxPixel, cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }

    private static func downsample(_ url: URL, maxPixel: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// One helper at a time, so a first open never fans out a dozen full-size decodes at once.
    private static let derivation = NSLock()

    /// A PNG never decodes partially, so a 6K screenshot costs its full bitmap for a 64px tile.
    private static func derivative(of url: URL, maxPixel: CGFloat) -> URL? {
        guard let copy = ImageDerivative.covering(url, maxPixel: Int(maxPixel.rounded(.up)))
        else { return nil }
        if exists(copy) { return copy.url }
        derivation.lock()
        defer { derivation.unlock() }
        if exists(copy) { return copy.url }
        // Only the copy asked for: a row never pays for a 1080px decode it does not show.
        guard let size = pixelSize(of: url), Int(max(size.width, size.height)) > copy.edge
        else { return nil }
        let helper = Process()
        helper.executableURL = Bundle.main.bundleURL
            .appending(path: "Contents/Helpers/ClipboardTextHelper", directoryHint: .notDirectory)
        helper.arguments = ["thumbnail", url.path, copy.url.path, String(copy.edge)]
        guard let exit = try? helper.runObservingExit() else { return nil }
        exit.wait()
        // The blob may have been deleted mid-run, after its cleanup already looked for this copy.
        guard FileManager.default.fileExists(atPath: url.path) else {
            try? FileManager.default.removeItem(at: copy.url)
            return nil
        }
        return exists(copy) ? copy.url : nil
    }

    private static func exists(_ copy: ImageDerivative) -> Bool {
        FileManager.default.fileExists(atPath: copy.url.path)
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
