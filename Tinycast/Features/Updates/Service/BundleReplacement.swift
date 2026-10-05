import Foundation

/// The last install step, split out so a harness can run it against a scratch folder.
enum BundleReplacement {
    /// A standard account can own the bundle without being able to write `/Applications`, which
    /// `replaceItemAt` needs. Swapping `Contents` needs only the two bundles, and `RENAME_SWAP` makes
    /// it one atomic step: the old `Contents` lands in `staged`, and a failure leaves both untouched.
    static func replace(_ bundle: URL, with staged: URL) throws {
        let files = FileManager.default
        guard !files.isWritableFile(atPath: bundle.deletingLastPathComponent().path),
            files.isWritableFile(atPath: bundle.path)
        else {
            _ = try files.replaceItemAt(bundle, withItemAt: staged, options: .usingNewMetadataOnly)
            return
        }
        let incoming = staged.appending(component: "Contents")
        let current = bundle.appending(component: "Contents")
        let swapped = incoming.withUnsafeFileSystemRepresentation { from in
            current.withUnsafeFileSystemRepresentation { to in
                renamex_np(from!, to!, UInt32(RENAME_SWAP))
            }
        }
        guard swapped == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
