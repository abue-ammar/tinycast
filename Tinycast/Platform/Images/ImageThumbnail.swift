import AppKit
import ImageIO
import Synchronization

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
    static func loadAsync(
        _ url: URL, maxPixel: CGFloat, copyingWith helper: URL? = nil
    ) async -> NSImage? {
        if let cached = cached(url, maxPixel: maxPixel) { return cached }
        var decodable = url
        if let helper, let copy = ImageDerivative.covering(url, maxPixel: Int(maxPixel.rounded(.up))),
            await makeCopy(copy, of: url, helper: helper)
        {
            decodable = copy.url
        }
        // A tile scrolled away mid-copy must not fall back to the full-size decode it was avoiding.
        guard !Task.isCancelled else { return nil }
        return await Task.detached(priority: .userInitiated) { [decodable] in
            if let image = decode(decodable, cachingAs: url, maxPixel: maxPixel) {
                return Decoded(image: image)
            }
            guard decodable != url else { return Decoded(image: nil) }
            // An unreadable copy is dropped so the next draw remakes it; the original shows now.
            ImageDerivative.queue.async { try? FileManager.default.removeItem(at: decodable) }
            return Decoded(image: decode(url, cachingAs: url, maxPixel: maxPixel))
        }.value.image
    }

    static func load(_ url: URL, maxPixel: CGFloat) -> NSImage? {
        if let cached = cached(url, maxPixel: maxPixel) { return cached }
        return decode(url, cachingAs: url, maxPixel: maxPixel)
    }

    private static func decode(_ file: URL, cachingAs url: URL, maxPixel: CGFloat) -> NSImage? {
        guard let cgImage = downsample(file, maxPixel: maxPixel) else { return nil }
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

    /// Waits on `ImageDerivative.queue`, off the cooperative pool, so a blob's delete waits it out.
    static func makeCopy(
        _ copy: ImageDerivative, of url: URL, helper: URL,
        timeout: DispatchTimeInterval = .seconds(10)
    ) async -> Bool {
        if exists(copy) { return true }
        let process = Process()
        process.executableURL = helper
        process.arguments = ["thumbnail", url.path, copy.url.path, String(copy.edge)]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let cancelled = Cancellation()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                ImageDerivative.queue.async {
                    let made = run(process, making: copy, of: url, timeout: timeout, cancelled: cancelled)
                    continuation.resume(returning: made)
                }
            }
        } onCancel: {
            cancelled.flag.withLock { $0 = true }
            terminate(process)
        }
    }

    private static func run(
        _ process: Process, making copy: ImageDerivative, of url: URL,
        timeout: DispatchTimeInterval, cancelled: Cancellation
    ) -> Bool {
        if exists(copy) { return true }
        guard !cancelled.flag.withLock({ $0 }), let size = pixelSize(of: url),
            Int(max(size.width, size.height)) > copy.edge,
            let exit = try? process.runObservingExit()
        else { return false }
        // A cancel between the check and the launch found nothing running to terminate.
        if cancelled.flag.withLock({ $0 }) { terminate(process) }
        let deadline = DispatchWorkItem { terminate(process) }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: deadline)
        exit.wait()
        deadline.cancel()
        return process.terminationStatus == 0 && exists(copy)
    }

    private final class Cancellation: Sendable {
        let flag = Mutex(false)
    }

    /// `terminate()` traps on a process that never launched, so the state has to be asked first.
    private static func terminate(_ process: Process) {
        if process.isRunning { process.terminate() }
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
