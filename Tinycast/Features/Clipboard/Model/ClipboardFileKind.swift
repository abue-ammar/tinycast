import Foundation
import UniformTypeIdentifiers

/// What a referenced file is, for the Type row and the tile a thumbnail has not filled yet.
enum ClipboardFileKind: Sendable {
    case image
    case movie
    case audio
    case pdf
    case folder
    case other

    /// Resolved from the extension, never from disk, so a vanished file still classifies.
    static func of(path: String, isDirectory: Bool = false) -> ClipboardFileKind {
        guard !isDirectory else { return .folder }
        let type = UTType(filenameExtension: URL(fileURLWithPath: path).pathExtension)
        guard let type else { return .other }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) { return .movie }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .pdf) { return .pdf }
        return .other
    }

    /// Whether the preview pane plays it rather than drawing a still.
    var isPlayable: Bool { self == .movie || self == .audio }

    var title: String {
        switch self {
        case .image: return "Image"
        case .movie: return "Movie"
        case .audio: return "Audio"
        case .pdf: return "PDF"
        case .folder: return "Folder"
        case .other: return "File"
        }
    }

    var systemImage: String {
        switch self {
        case .image: return "photo"
        case .movie: return "film"
        case .audio: return "waveform"
        case .pdf: return "doc.richtext"
        case .folder: return "folder"
        case .other: return "doc"
        }
    }
}
