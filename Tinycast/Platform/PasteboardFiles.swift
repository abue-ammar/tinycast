import AppKit

/// The files a pasteboard names; `NSURL` reading picks a representation of its own choosing.
enum PasteboardFiles {
    /// Written by anything that still speaks the pre-UTI pasteboard.
    private static let legacyFilenames = NSPasteboard.PasteboardType("NSFilenamesPboardType")

    /// Empty when the board names no file, so a caller falls through to text or bytes.
    static func urls(on pasteboard: NSPasteboard) -> [URL] {
        let items = (pasteboard.pasteboardItems ?? []).compactMap(url(from:))
        if !items.isEmpty { return items }
        guard let paths = pasteboard.propertyList(forType: legacyFilenames) as? [String] else {
            return []
        }
        return paths.map { URL(fileURLWithPath: $0) }
    }

    /// `public.file-url` arrives as UTF-8 data on most boards and as a string on some.
    private static func url(from item: NSPasteboardItem) -> URL? {
        if let data = item.data(forType: .fileURL),
            let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL
        {
            return url
        }
        guard let string = item.string(forType: .fileURL), let url = URL(string: string),
            url.isFileURL
        else { return nil }
        return url
    }
}
