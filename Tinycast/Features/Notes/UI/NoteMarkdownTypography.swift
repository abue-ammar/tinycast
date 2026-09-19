import AppKit

/// The editor's `NSFont`s: the system text styles one step up, since a note is for reading.
@MainActor
struct NoteMarkdownTypography {
    /// Notes takes the interface font but never the Interface Size, which it has always sat above.
    static let system = NoteMarkdownTypography(fontFamily: nil)

    let fontFamily: String?
    /// Resolved once: the styler reads these per line per keystroke, where a lookup would show.
    let body: NSFont
    let heading1: NSFont
    let heading2: NSFont
    let heading3: NSFont
    let inlineCode: NSFont
    let codeBlock: NSFont
    /// Small enough that a hidden marker leaves no visible gap, while staying a real glyph run.
    let hidden = NSFont.systemFont(ofSize: 0.01)

    init(fontFamily: String?) {
        self.fontFamily = fontFamily
        func face(_ points: CGFloat, _ weight: NSFont.Weight) -> NSFont {
            let system = NSFont.systemFont(ofSize: points, weight: weight)
            return InterfaceMetrics.face(system, on: fontFamily, size: points) ?? system
        }
        func size(_ style: NSFont.TextStyle) -> CGFloat {
            NSFont.preferredFont(forTextStyle: style).pointSize
        }
        body = face(size(.title3), .regular)
        heading1 = face(size(.largeTitle), .bold)
        heading2 = face(size(.title1), .bold)
        heading3 = face(size(.title2), .semibold)
        inlineCode = Self.mono(body.pointSize, on: fontFamily)
        codeBlock = Self.mono(body.pointSize - 1, on: fontFamily)
    }

    /// Levels 4 to 6 share the third heading's style.
    func heading(_ level: Int) -> NSFont {
        switch level {
        case 1: heading1
        case 2: heading2
        default: heading3
        }
    }

    func adding(_ traits: NSFontDescriptor.SymbolicTraits, to font: NSFont) -> NSFont {
        let current = font.fontDescriptor.symbolicTraits
        let descriptor = font.fontDescriptor.withSymbolicTraits(current.union(traits))
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }

    func inlineCode(matching font: NSFont) -> NSFont {
        font.pointSize == body.pointSize ? inlineCode : Self.mono(font.pointSize, on: fontFamily)
    }

    /// A chosen family is the one font everywhere, so it outranks the monospaced design here too.
    private static func mono(_ points: CGFloat, on family: String?) -> NSFont {
        let system = NSFont.monospacedSystemFont(ofSize: points, weight: .regular)
        return InterfaceMetrics.face(system, on: family, size: points) ?? system
    }
}
