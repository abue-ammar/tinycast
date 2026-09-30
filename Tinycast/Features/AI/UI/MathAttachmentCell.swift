import AppKit

/// One typeset formula in a reply's text view, drawn from its layout in the text's own colour.
final class MathAttachmentCell: NSTextAttachmentCell {
    private let box: MathBox
    private let color: NSColor
    /// Layout asks for the size off the main actor, so the extent is kept apart from the drawing.
    private nonisolated let width: CGFloat
    private nonisolated let ascent: CGFloat
    private nonisolated let descent: CGFloat

    init(box: MathBox, color: NSColor, label: String) {
        self.box = box
        self.color = color
        width = box.width
        ascent = box.ascent
        descent = box.descent
        super.init()
        // Without a role the attachment reaches VoiceOver as an unknown element.
        setAccessibilityRole(.image)
        setAccessibilityLabel(label)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("A formula is never decoded") }

    override func cellSize() -> NSSize { NSSize(width: width, height: ascent + descent) }

    override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: -descent) }

    /// Wider than its line, as a long equation in Quick AI is, it shrinks rather than overflows.
    override func cellFrame(
        for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect,
        glyphPosition position: NSPoint, characterIndex charIndex: Int
    ) -> NSRect {
        let available = lineFrag.width - textContainer.lineFragmentPadding * 2
        let scale = width > available && available > 0 ? available / width : 1
        return NSRect(x: 0, y: -descent * scale, width: width * scale, height: (ascent + descent) * scale)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        guard box.width > 0, let context = NSGraphicsContext.current?.cgContext else { return }
        let scale = cellFrame.width / box.width
        context.saveGState()
        defer { context.restoreGState() }
        if controlView?.isFlipped ?? true {
            context.translateBy(x: cellFrame.minX, y: cellFrame.maxY)
            context.scaleBy(x: scale, y: -scale)
        } else {
            context.translateBy(x: cellFrame.minX, y: cellFrame.minY)
            context.scaleBy(x: scale, y: scale)
        }
        context.translateBy(x: 0, y: box.descent)
        context.setFillColor(color.cgColor)
        box.draw(in: context)
    }

    override func wantsToTrackMouse() -> Bool { false }
}
