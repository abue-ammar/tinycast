import Foundation
import UniformTypeIdentifiers

enum FileSearchPreviewKind: Equatable, Sendable {
    case quickLook
    /// QuickLook draws a PDF out of process, and that remote view never scrolls in the palette.
    case pdf
    /// QuickLook draws a movie's first frame but never plays one inside a non-activating panel.
    case media
    /// Text QuickLook would draw as an icon: it renders only a declared `public.text` as text.
    case text

    /// Nil when only the bytes can tell: an undeclared type, or `.ts`, TypeScript or MPEG-TS video.
    init?(pathExtension: String) {
        guard let type = UTType(filenameExtension: pathExtension), !type.isDynamic,
            !type.conforms(to: .mpeg2TransportStream)
        else { return nil }
        self = Self.declared(type)
    }

    /// For an extension that left it open: text if the bytes are, otherwise what it declares.
    init(pathExtension: String, head: Data, isWholeFile: Bool) {
        guard !Self.isText(head, isWholeFile: isWholeFile) else {
            self = .text
            return
        }
        self = UTType(filenameExtension: pathExtension).map(Self.declared) ?? .quickLook
    }

    private static func declared(_ type: UTType) -> Self {
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .movie) || type.conforms(to: .audio) { return .media }
        return .quickLook
    }

    /// No NUL and valid UTF-8, forgiving the one character a partial read may have cut in half.
    static func isText(_ bytes: Data, isWholeFile: Bool) -> Bool {
        guard !bytes.contains(0) else { return false }
        let checked = isWholeFile ? bytes : bytes.dropLast(cutCharacterLength(bytes))
        return String(validating: checked, as: UTF8.self) != nil
    }

    /// The bytes of a trailing multi-byte character that is missing its continuation bytes.
    private static func cutCharacterLength(_ bytes: Data) -> Int {
        guard let lead = bytes.suffix(3).lastIndex(where: { $0 & 0xC0 != 0x80 }) else { return 0 }
        let length =
            switch bytes[lead] {
            case 0xC2...0xDF: 2
            case 0xE0...0xEF: 3
            case 0xF0...0xF4: 4
            default: 1
            }
        let present = bytes.endIndex - lead
        return present < length ? present : 0
    }
}
