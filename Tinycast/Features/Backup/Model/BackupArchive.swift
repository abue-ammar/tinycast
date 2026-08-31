import AppleArchive
import Foundation
import System

/// Seals a `BackupBundle` directory into one `.tinycast` file, and opens one back up.
enum BackupArchive {
    static let fileExtension = "tinycast"

    enum ArchiveError: LocalizedError, Equatable {
        case cannotWrite
        case cannotRead

        var errorDescription: String? {
            switch self {
            case .cannotWrite: return "Couldn't write the backup file."
            case .cannotRead: return "This file isn't a Tinycast backup, or it's damaged."
            }
        }
    }

    /// No `UID`/`GID` to restore a foreign owner, no `IDX` to dangle; `MTM` feeds the note sort.
    private static var keySet: ArchiveHeader.FieldKeySet? {
        ArchiveHeader.FieldKeySet("TYP,PAT,DAT,MOD,MTM")
    }

    /// LZFSE, not LZMA: the payload is dominated by PNGs that are already compressed.
    static func seal(directory: URL, into file: URL) throws {
        guard let keySet,
            let destination = ArchiveByteStream.fileStream(
                path: FilePath(file.path), mode: .writeOnly, options: [.create, .truncate],
                permissions: FilePermissions(rawValue: 0o600)),
            let compressor = ArchiveByteStream.compressionStream(
                using: .lzfse, writingTo: destination)
        else { throw ArchiveError.cannotWrite }
        var sealed = false
        defer {
            if !sealed {
                try? compressor.close()
                try? destination.close()
            }
        }
        try ArchiveStream.withEncodeStream(writingTo: compressor) { encoder in
            try encoder.writeDirectoryContents(
                archiveFrom: FilePath(directory.path), keySet: keySet)
        }
        // Explicit, not `try?`: the last block flushes in `close`, so a truncated write must throw.
        try compressor.close()
        try destination.close()
        sealed = true
    }

    static func open(file: URL, into directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard
            let source = ArchiveByteStream.fileStream(
                path: FilePath(file.path), mode: .readOnly, options: [], permissions: []),
            let decompressor = ArchiveByteStream.decompressionStream(readingFrom: source)
        else { throw ArchiveError.cannotRead }
        defer {
            try? decompressor.close()
            try? source.close()
        }
        guard let decoder = ArchiveStream.decodeStream(readingFrom: decompressor) else {
            throw ArchiveError.cannotRead
        }
        defer { try? decoder.close() }
        do {
            try ArchiveStream.withExtractStream(
                extractingTo: FilePath(directory.path), selectUsing: containedEntry
            ) { extractor in
                _ = try ArchiveStream.process(readingFrom: decoder, writingTo: extractor)
            }
        } catch {
            throw ArchiveError.cannotRead
        }
        guard !containsSymbolicLink(directory) else { throw ArchiveError.cannotRead }
    }

    /// A link entry passes the path filter, and reading through one would leave the extract.
    private static func containsSymbolicLink(_ directory: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey]
        guard
            let entries = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: Array(keys))
        else { return true }
        for case let url as URL in entries
        where (try? url.resourceValues(forKeys: keys))?.isSymbolicLink == true {
            return true
        }
        return false
    }

    /// Skips any entry naming an absolute path or `..`, so a hostile archive cannot escape.
    private static func containedEntry(
        _ message: ArchiveHeader.EntryMessage, _ path: FilePath,
        _ data: ArchiveHeader.EntryFilterData?
    ) -> ArchiveHeader.EntryMessageStatus {
        guard !path.isAbsolute, !path.components.contains(where: { $0.string == ".." }) else {
            return .skip
        }
        return .ok
    }
}
