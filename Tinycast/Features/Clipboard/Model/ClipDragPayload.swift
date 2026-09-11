import Foundation

/// What a row hands to the app it is dropped on.
enum ClipDragPayload: Equatable, Sendable {
    case file(URL)
    /// A browser reads `public.url`, a text field reads the string.
    case link(URL, String)
    case text(String)
}

extension ClipboardItem {
    /// `textForm` stays the one answer to a link, so the drag and the type filter cannot disagree.
    var dragPayload: ClipDragPayload {
        if let path = imagePath ?? filePath { return .file(URL(fileURLWithPath: path)) }
        let copy = text ?? ""
        guard textForm == .link else { return .text(copy) }
        switch QuicklinkDestination.detect(copy) {
        case .web(let url), .network(let url), .deeplink(let url): return .link(url, copy)
        case .path, nil: return .text(copy)
        }
    }
}
