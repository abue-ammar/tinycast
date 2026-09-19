import AppKit

/// The editor's `NSFont`s: the system text styles one step up, since a note is for reading.
struct NoteMarkdownTypography: Sendable {
    /// Notes takes the interface font but never the Interface Size, which it has always sat above.
    static let system = NoteMarkdownTypography(fontFamily: nil)

    let fontFamily: String?

    var body: NSFont { face(size(.title3), .regular) }
    var heading1: NSFont { face(size(.largeTitle), .bold) }
    var heading2: NSFont { face(size(.title1), .bold) }
    var heading3: NSFont { face(size(.title2), .semibold) }
    var inlineCode: NSFont { mono(body.pointSize) }
    var codeBlock: NSFont { mono(body.pointSize - 1) }
    /// Small enough that a hidden marker leaves no visible gap, while staying a real glyph run.
    var hidden: NSFont { NSFont.systemFont(ofSize: 0.01) }

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
        font.pointSize == body.pointSize ? inlineCode : mono(font.pointSize)
    }

    private func face(_ points: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let system = NSFont.systemFont(ofSize: points, weight: weight)
        return InterfaceMetrics.face(system, on: fontFamily, size: points) ?? system
    }

    /// A chosen family is the one font everywhere, so it outranks the monospaced design here too.
    private func mono(_ points: CGFloat) -> NSFont {
        let system = NSFont.monospacedSystemFont(ofSize: points, weight: .regular)
        return InterfaceMetrics.face(system, on: fontFamily, size: points) ?? system
    }

    private func size(_ style: NSFont.TextStyle) -> CGFloat {
        NSFont.preferredFont(forTextStyle: style).pointSize
    }
}
