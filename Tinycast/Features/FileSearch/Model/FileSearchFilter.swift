import Foundation
import UniformTypeIdentifiers

/// The Search Files header filter. See docs/features/file-search.md#type-filter.
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
        case .all: return "All Types"
        case .folders: return "Folders"
        case .documents: return "Documents"
        case .images: return "Images"
        case .audio: return "Audio"
        case .video: return "Videos"
        case .archives: return "Archives"
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
        case .all: return "No files found"
        case .folders: return "No folders found"
        case .documents: return "No documents found"
        case .images: return "No images found"
        case .audio: return "No audio found"
        case .video: return "No videos found"
        case .archives: return "No archives found"
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

    /// Filtering in the predicate keeps the rejected types from consuming the candidate cap.
    var spotlightClause: String? {
        let clauses = contentTypes.map { "kMDItemContentTypeTree == \"\($0.identifier)\"" }
        guard let first = clauses.first else { return nil }
        guard clauses.count > 1 else { return first }
        return "(" + clauses.joined(separator: " || ") + ")"
    }

    /// The home-root branch never reaches Spotlight, so it answers the same question locally.
    func accepts(contentType: UTType?, isDirectory: Bool) -> Bool {
        guard self != .all else { return true }
        // An unresolved type is only ever a plain directory: everything else carries one.
        guard let contentType else { return self == .folders && isDirectory }
        return contentTypes.contains { contentType.conforms(to: $0) }
    }
}
