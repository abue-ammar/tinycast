import Foundation
import UniformTypeIdentifiers

enum FileSearchFilter: CaseIterable, Sendable {
    case all
    case folders
    case documents
    case images
    case audio
    case video
    case archives

    var title: String {
        switch self {
        case .all: return String(localized: "All Types")
        case .folders: return String(localized: "Folders")
        case .documents: return String(localized: "Documents")
        case .images: return String(localized: "Images")
        case .audio: return String(localized: "Audio")
        case .video: return String(localized: "Videos")
        case .archives: return String(localized: "Archives")
        }
    }

    /// Also the header button's glyph, so it states the active filter without opening the menu.
    var systemImage: String {
        switch self {
        case .all: return "list.bullet"
        case .folders: return "folder"
        case .documents: return "doc.text"
        case .images: return "photo"
        case .audio: return "waveform"
        case .video: return "film"
        case .archives: return "archivebox"
        }
    }

    /// What an empty list says, so a filter hiding every match explains itself.
    var emptyMessage: String {
        switch self {
        case .all: return String(localized: "No files found")
        case .folders: return String(localized: "No folders found")
        case .documents: return String(localized: "No documents found")
        case .images: return String(localized: "No images found")
        case .audio: return String(localized: "No audio found")
        case .video: return String(localized: "No videos found")
        case .archives: return String(localized: "No archives found")
        }
    }

    /// The types a case admits; `all` names none, which is what keeps an unfiltered search free.
    var contentTypes: [UTType] {
        switch self {
        case .all: return []
        case .folders: return [.folder]
        case .documents: return [.text, .compositeContent, .spreadsheet, .presentation, .pdf]
        case .images: return [.image]
        case .audio: return [.audio]
        case .video: return [.movie]
        case .archives: return [.archive]
        }
    }

    func accepts(contentType: UTType?, isDirectory: Bool) -> Bool {
        guard self != .all else { return true }
        // An unresolved type is only ever a plain directory: everything else carries one.
        guard let contentType else { return self == .folders && isDirectory }
        return contentTypes.contains { contentType.conforms(to: $0) }
    }

    /// The index records no type, and a stat per row would cost more than the extension.
    static func contentType(extension pathExtension: String, isDirectory: Bool) -> UTType? {
        guard !pathExtension.isEmpty else { return isDirectory ? .folder : nil }
        guard isDirectory else { return UTType(filenameExtension: pathExtension) }
        // A folder named `v1.2` is still a folder; only a declared package is a document.
        let package = UTType(filenameExtension: pathExtension, conformingTo: .package)
        return package.flatMap { $0.isDeclared ? $0 : nil } ?? .folder
    }
}
