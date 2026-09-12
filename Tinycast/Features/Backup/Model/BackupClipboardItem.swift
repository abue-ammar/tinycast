import Foundation

/// A clip in portable form: not `ClipboardItem`, whose `imagePath` names a file on one Mac.
struct BackupClipboardItem: Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable {
        case text
        case image
        case file
    }

    var kind: Kind
    var text: String?
    /// A filename inside the bundle's `clipboard/images/`, never a path.
    var imageName: String?
    var createdAt: Date
    var sourceBundleID: String?
    var pinnedAt: Date?
}
