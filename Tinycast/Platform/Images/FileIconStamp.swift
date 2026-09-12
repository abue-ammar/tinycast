import Foundation

/// A pasted icon writes `Icon\r` inside the bundle and flips a FinderInfo bit.
enum FileIconStamp {
    private static let keys: Set<URLResourceKey> = [
        .contentModificationDateKey, .attributeModificationDateKey, .fileSizeKey
    ]

    static func value(for url: URL) -> Int {
        var hasher = Hasher()
        combine(url, into: &hasher)
        combine(URL(fileURLWithPath: url.path + "/Icon\r"), into: &hasher)
        return hasher.finalize()
    }

    /// A path that does not exist adds nothing, so gaining `Icon\r` moves the stamp.
    private static func combine(_ url: URL, into hasher: inout Hasher) {
        guard let values = try? url.resourceValues(forKeys: keys) else { return }
        hasher.combine(values.contentModificationDate)
        hasher.combine(values.attributeModificationDate)
        hasher.combine(values.fileSize)
    }
}
