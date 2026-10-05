import AppKit
import CryptoKit
import ImageIO

/// On-demand fetcher and disk/memory cache for Open Graph link metadata and images.
@MainActor
enum LinkOGImageStore {
    private static let cache = ThumbnailCache(
        rowBytes: 8 * 1024 * 1024, previewBytes: 32 * 1024 * 1024)

    private static var metadataCache: [URL: LinkMetadata] = [:]
    private static var inFlight: [URL: Task<(image: NSImage?, metadata: LinkMetadata?), Never>] = [:]

    private static let diskDirectory: URL = {
        let dir = AppPaths.caches().appendingPathComponent("LinkOGImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Ephemeral session with no URLCache so the disk cache remains the single copy.
    private nonisolated static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()

    /// Cache-only, never touching disk or network, so a warm preview paints at 60fps.
    static func cached(_ url: URL, maxPixel: CGFloat) -> NSImage? {
        cache.cached(url, maxPixel: maxPixel)
    }

    /// Reads metadata from memory or disk cache without triggering network activity.
    static func cachedMetadata(_ url: URL) -> LinkMetadata? {
        if let hit = metadataCache[url] { return hit }
        let metaFile = diskMetadataFile(for: url)
        guard let data = try? Data(contentsOf: metaFile),
            let decoded = try? JSONDecoder().decode(LinkMetadata.self, from: data)
        else { return nil }
        metadataCache[url] = decoded
        return decoded
    }

    /// Drops preview bitmaps when the palette closes to return RAM near baseline.
    static func purgePreviews() {
        cache.purgePreviews()
    }

    /// Loads metadata on demand, resolving via cache first and network when needed.
    static func loadMetadataAsync(_ url: URL) async -> LinkMetadata? {
        if let hit = cachedMetadata(url) { return hit }
        let result = await loadAsync(url, maxPixel: 900)
        return result.metadata
    }

    /// Loads the preview image and metadata: memory first, disk second, network last.
    static func loadAsync(_ url: URL, maxPixel: CGFloat) async -> (image: NSImage?, metadata: LinkMetadata?) {
        let memImage = cached(url, maxPixel: maxPixel)
        let memMeta = cachedMetadata(url)
        if let memImage, let memMeta { return (memImage, memMeta) }

        let imgFile = diskImageFile(for: url)
        var diskImage: NSImage?
        if FileManager.default.fileExists(atPath: imgFile.path) {
            if let image = ImageThumbnail.load(imgFile, maxPixel: maxPixel) {
                let cost = Int(image.size.width * image.size.height * 4)
                cache.store(image, for: url, maxPixel: maxPixel, cost: cost)
                diskImage = image
            }
        }

        let diskMeta = memMeta ?? cachedMetadata(url)
        if let diskImage, let diskMeta {
            return (diskImage, diskMeta)
        }
        if diskImage == nil, let diskMeta, diskMeta.imageURL == nil {
            return (nil, diskMeta)
        }

        if let existing = inFlight[url] {
            return await existing.value
        }

        let task = Task<(image: NSImage?, metadata: LinkMetadata?), Never> {
            defer { inFlight[url] = nil }
            return await fetchAndCache(url: url, maxPixel: maxPixel)
        }
        inFlight[url] = task
        return await task.value
    }

    private static func fetchAndCache(url: URL, maxPixel: CGFloat) async -> (image: NSImage?, metadata: LinkMetadata?) {
        let imgFile = diskImageFile(for: url)
        let metaFile = diskMetadataFile(for: url)

        if LinkMetadataParser.isDirectImageURL(url) {
            guard let data = await fetchDirectImage(url: url), !data.isEmpty else { return (nil, nil) }
            try? data.write(to: imgFile, options: .atomic)
            let meta = LinkMetadata(title: url.lastPathComponent, description: nil, imageURL: url)
            if let encoded = try? JSONEncoder().encode(meta) {
                try? encoded.write(to: metaFile, options: .atomic)
            }
            metadataCache[url] = meta
            let image = await decodeThumbnail(from: data, maxPixel: maxPixel, for: url)
            return (image, meta)
        }

        let metadata: LinkMetadata
        if let cached = cachedMetadata(url) {
            metadata = cached
        } else {
            guard let payload = await fetchHTMLAndMetadata(url: url) else { return (nil, nil) }

            if let directData = payload.directImageData {
                try? directData.write(to: imgFile, options: .atomic)
                let meta = LinkMetadata(title: url.lastPathComponent, description: nil, imageURL: url)
                if let encoded = try? JSONEncoder().encode(meta) {
                    try? encoded.write(to: metaFile, options: .atomic)
                }
                metadataCache[url] = meta
                let image = await decodeThumbnail(from: directData, maxPixel: maxPixel, for: url)
                return (image, meta)
            }

            guard let parsed = payload.metadata else { return (nil, nil) }
            if let encoded = try? JSONEncoder().encode(parsed) {
                try? encoded.write(to: metaFile, options: .atomic)
            }
            metadataCache[url] = parsed
            metadata = parsed
        }

        var image: NSImage?
        if let imageURL = metadata.imageURL, let imgData = await fetchDirectImage(url: imageURL), !imgData.isEmpty {
            try? imgData.write(to: imgFile, options: .atomic)
            image = await decodeThumbnail(from: imgData, maxPixel: maxPixel, for: url)
        }

        return (image, metadata)
    }

    private static func decodeThumbnail(from data: Data, maxPixel: CGFloat, for url: URL) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return Decoded(image: nil) }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            else { return Decoded(image: nil) }
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            let cost = cgImage.bytesPerRow * cgImage.height
            Task { @MainActor in
                cache.store(image, for: url, maxPixel: maxPixel, cost: cost)
            }
            return Decoded(image: image)
        }.value.image
    }

    private nonisolated static func fetchDirectImage(url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent")
        request.setValue("image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
            let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            data.count <= 10 * 1024 * 1024
        else { return nil }
        return data
    }

    private struct HTMLPayload: Sendable {
        var directImageData: Data?
        var metadata: LinkMetadata?
    }

    private nonisolated static func fetchHTMLAndMetadata(url: URL) async -> HTMLPayload? {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent")
        request.setValue(
            "text/html,application/xhtml+xml,application/xml;q=0.9,image/*,*/*;q=0.8",
            forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
            let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return nil }

        // Some servers serve images directly without extension or after redirect.
        if let mime = http.mimeType?.lowercased(), mime.hasPrefix("image/"), data.count <= 10 * 1024 * 1024 {
            return HTMLPayload(directImageData: data, metadata: nil)
        }

        // Only parse the first 256KB of the page to avoid buffering megabytes of body.
        let capped = data.prefix(256 * 1024)
        guard let html = String(data: capped, encoding: .utf8)
            ?? String(data: capped, encoding: .isoLatin1)
        else { return nil }

        let baseURL = response.url ?? url
        let metadata = LinkMetadataParser.extractMetadata(from: html, baseURL: baseURL)
        return HTMLPayload(directImageData: nil, metadata: metadata)
    }

    private static func urlHash(_ url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func diskImageFile(for url: URL) -> URL {
        diskDirectory.appendingPathComponent(urlHash(url) + ".img")
    }

    private static func diskMetadataFile(for url: URL) -> URL {
        diskDirectory.appendingPathComponent(urlHash(url) + ".json")
    }

    /// A freshly-decoded NSImage moved safely across actor boundaries.
    private struct Decoded: @unchecked Sendable {
        let image: NSImage?
    }
}
