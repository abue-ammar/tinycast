import Foundation

/// A smaller copy of an immutable image blob, kept beside it so a tile never decodes the original.
struct ImageDerivative: Sendable {
    /// Longest edges a copy is written at; a request decodes the smallest one that covers it.
    static let edges = [256, 1080]

    /// Serial for making and deleting copies: a delete waits out the copy in flight, never the reverse.
    static let queue = DispatchQueue(label: "com.tinycast.image-derivative", qos: .userInitiated)

    let url: URL
    let edge: Int

    /// Nil past the largest edge, where only the original is sharp enough.
    static func covering(_ original: URL, maxPixel: Int) -> ImageDerivative? {
        edges.first { $0 >= maxPixel }.map { ImageDerivative(original, edge: $0) }
    }

    /// Every copy a blob may have, so deleting the blob leaves none behind.
    static func all(of original: URL) -> [ImageDerivative] {
        edges.map { ImageDerivative(original, edge: $0) }
    }

    /// Queued, so it runs after any copy of this blob being written and off the caller's thread.
    static func removeCopies(of original: URL) {
        queue.async {
            for copy in all(of: original) { try? FileManager.default.removeItem(at: copy.url) }
        }
    }

    /// Copies whose blob is gone, which a quit before `removeCopies` ran leaves behind.
    static func removeOrphans(in directory: URL) {
        queue.async {
            let folder = directory.appending(path: ".thumbnails", directoryHint: .isDirectory)
            for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] {
                guard let edge = name.lastIndex(of: "-") else { continue }
                let blob = directory.appending(path: String(name[..<edge]))
                guard !FileManager.default.fileExists(atPath: blob.path) else { continue }
                try? FileManager.default.removeItem(at: folder.appending(path: name))
            }
        }
    }

    static func folder(beside original: URL) -> URL {
        original.deletingLastPathComponent()
            .appending(path: ".thumbnails", directoryHint: .isDirectory)
    }

    /// Keyed by the whole file name, so `a.jpg` and `a.png` never share a copy.
    private init(_ original: URL, edge: Int) {
        url = Self.folder(beside: original)
            .appending(path: "\(original.lastPathComponent)-\(edge).png", directoryHint: .notDirectory)
        self.edge = edge
    }
}
