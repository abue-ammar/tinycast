import Foundation
import UniformTypeIdentifiers

/// Pure filesystem metadata probe for `FileSearchResult`, safe for off-main execution.
struct FileMetadataProbe: Equatable, Sendable {
    var exists = false
    var isDirectory = false
    var typeName: String?
    var fileBytes: Int64?
    var creationDate: Date?
    var modificationDate: Date?
    var accessDate: Date?

    /// Medium date and time formatter; cached per thread / caller for deterministic formatting.
    @MainActor private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    /// Relative date formatter for last access dates.
    @MainActor private static let relativeDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    nonisolated static func probe(url: URL) -> FileMetadataProbe {
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else {
            return FileMetadataProbe(exists: false)
        }
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .fileSizeKey,
            .contentTypeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .contentAccessDateKey,
        ]
        let values = try? url.resourceValues(forKeys: keys)
        let isDir = values?.isDirectory ?? false
        let typeName = values?.contentType?.localizedDescription
            ?? (isDir ? "Folder" : "File")
        let bytes = values?.fileSize.map(Int64.init)
        return FileMetadataProbe(
            exists: true,
            isDirectory: isDir,
            typeName: typeName,
            fileBytes: bytes,
            creationDate: values?.creationDate,
            modificationDate: values?.contentModificationDate,
            accessDate: values?.contentAccessDate
        )
    }

    static func formatBytes(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }

    @MainActor static func formatDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    @MainActor static func formatAccessedDate(_ date: Date) -> String {
        relativeDateFormatter.string(from: date)
    }
}
