import Foundation

/// A guard, not a routine step: an archive Tinycast fetched itself is not quarantined.
enum Quarantine {
    private static let attribute = "com.apple.quarantine"

    static func isSet(on url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return getxattr(path, attribute, nil, 0, 0, XATTR_NOFOLLOW) >= 0
        }
    }

    /// Expanding a quarantined archive marks every file it wrote, not just the root.
    static func clear(from root: URL) {
        remove(from: root)
        guard
            let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: nil)
        else { return }
        for case let url as URL in walker { remove(from: url) }
    }

    private static func remove(from url: URL) {
        _ = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(0) }
            return removexattr(path, attribute, XATTR_NOFOLLOW)
        }
    }
}
