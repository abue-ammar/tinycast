import AppKit
import SwiftUI

/// One AppKit text view per segment, since SwiftUI's `Text` selects only within one paragraph.
struct ChatMarkdownText: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.chatTextHighlight) private var highlight
    @Environment(\.chatCitations) private var citations
    @Environment(\.chatFindPath) private var path
    let blocks: [MarkdownBlock]
    var failedFrom: Int?

    /// Where the current find match sits in this text, so the transcript can scroll to it.
    @State private var currentMatch: CGRect?

    private var holdsCurrentMatch: Bool {
        guard let leaf = highlight?.current?.leaf else { return false }
        return leaf.starts(with: path)
    }

    var body: some View {
        ChatTextRepresentable(
            source: ChatMarkdownSource(
                blocks: blocks, highlight: highlight, citations: citations, prefix: path,
                failedFrom: failedFrom, metrics: metrics)
        ) { rect in
            if rect != currentMatch { currentMatch = rect }
        }
        .overlay(alignment: .topLeading) {
            if holdsCurrentMatch, let rect = currentMatch {
                Color.clear
                    .frame(width: max(rect.width, 1), height: max(rect.height, 1))
                    .offset(x: rect.minX, y: rect.minY)
                    .id(ChatTextHighlight.currentAnchor)
            }
        }
    }
}

private struct ChatTextRepresentable: NSViewRepresentable {
    let source: ChatMarkdownSource
    let onCurrentMatch: (CGRect?) -> Void

    func makeNSView(context: Context) -> ChatSelectableTextView { ChatSelectableTextView() }

    func updateNSView(_ view: ChatSelectableTextView, context: Context) {
        view.onCurrentMatch = onCurrentMatch
        view.show(source)
    }

    /// An open width asks for the ideal, as `Text` answers it: every paragraph on one line.
    func sizeThatFits(
        _ proposal: ProposedViewSize, nsView view: ChatSelectableTextView, context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width.isFinite else { return view.measure(width: nil) }
        return CGSize(width: width, height: view.measure(width: width).height)
    }
}

/// Read-only and backgroundless; it wraps to its frame and leaves scrolling to the transcript.
final class ChatSelectableTextView: NSTextView {
    var onCurrentMatch: ((CGRect?) -> Void)?
    private var source: ChatMarkdownSource?
    private var rendered: ChatRenderedText?
    private var headers: [ChatCodeHeader] = []
    private var codeBoxes: [CGRect] = []
    private var reportedMatch: CGRect?
    /// A second layout of the same storage, so SwiftUI's size probes never re-wrap the drawn one.
    private let measurer = NSLayoutManager()
    private let measuringContainer = NSTextContainer(size: .zero)
    private var measured: (width: CGFloat?, size: CGSize)?

    init() {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(
            size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        measuringContainer.lineFragmentPadding = 0
        measurer.addTextContainer(measuringContainer)
        storage.addLayoutManager(measurer)
        super.init(frame: .zero, textContainer: container)
        isEditable = false
        isSelectable = true
        isRichText = true
        drawsBackground = false
        textContainerInset = .zero
        isVerticallyResizable = false
        isHorizontallyResizable = false
        allowsUndo = false
        linkTextAttributes = [.foregroundColor: NSColor.linkColor, .cursor: NSCursor.pointingHand]
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// Re-rendered only when its source changed, so a finished reply keeps its selection.
    func show(_ next: ChatMarkdownSource) {
        guard next != source else { return }
        source = next
        let output = ChatMarkdownRenderer(next).render()
        rendered = output
        measured = nil
        textStorage?.setAttributedString(output.string)
        layoutOverlays()
        needsDisplay = true
    }

    /// `nil` is the ideal width. SwiftUI asks the same width repeatedly, so the last answer is kept.
    func measure(width: CGFloat?) -> CGSize {
        if let measured, measured.width == width { return measured.size }
        measuringContainer.size = CGSize(
            width: width ?? .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        measurer.ensureLayout(for: measuringContainer)
        let used = measurer.usedRect(for: measuringContainer)
        let size = CGSize(width: ceil(used.width), height: ceil(used.height))
        measured = (width, size)
        return size
    }

    /// An equation copies, drags and serves as the LaTeX the reply wrote rather than as a picture.
    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        guard let storage = textStorage else { return super.writeSelection(to: pboard, types: types) }
        let ranges = selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
        let holdsMath = ranges.contains { range in
            var found = false
            storage.enumerateAttribute(ChatMarkdownRenderer.mathSource, in: range) { value, _, stop in
                found = value != nil
                stop.pointee = ObjCBool(found)
            }
            return found
        }
        guard holdsMath else { return super.writeSelection(to: pboard, types: types) }
        let copied = NSMutableAttributedString()
        for (index, range) in ranges.enumerated() {
            if index > 0 { copied.append(NSAttributedString(string: "\n")) }
            copied.append(Self.writingMathSource(storage.attributedSubstring(from: range)))
        }
        pboard.clearContents()
        return pboard.writeObjects([copied])
    }

    private static func writingMathSource(_ text: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        let key = ChatMarkdownRenderer.mathSource
        let whole = NSRange(location: 0, length: result.length)
        result.enumerateAttribute(key, in: whole, options: .reverse) { value, range, _ in
            guard let source = value as? String else { return }
            var attributes = result.attributes(at: range.location, effectiveRange: nil)
            attributes[.attachment] = nil
            attributes[key] = nil
            let replacement = String(repeating: source, count: range.length)
            result.replaceCharacters(
                in: range, with: NSAttributedString(string: replacement, attributes: attributes))
        }
        return result
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutOverlays()
    }

    override func mouseMoved(with event: NSEvent) {
        guard ownsPointer() else {
            NSCursor.arrow.set()
            return
        }
        super.mouseMoved(with: event)
    }

    override func cursorUpdate(with event: NSEvent) {
        guard ownsPointer() else {
            NSCursor.arrow.set()
            return
        }
        super.cursorUpdate(with: event)
    }

    /// The tracking area hears the pointer under a code header or anything floated over the text.
    private func ownsPointer() -> Bool {
        guard let window, let hit = window.contentView?.hitTest(window.mouseLocationOutsideOfEventStream)
        else { return false }
        return hit === self
            || (hit.isDescendant(of: self) && !headers.contains { hit.isDescendant(of: $0) })
    }

    /// A text block paints only around drawn glyphs, so a redraw of its header strip skipped it.
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let metrics = source?.metrics, let context = NSGraphicsContext.current?.cgContext else {
            return
        }
        let line = Theme.Size.hairline
        for box in codeBoxes where box.intersects(rect) {
            let path = RoundedRectangle(cornerRadius: metrics.radius.codeBlock, style: .continuous)
                .path(in: box.insetBy(dx: line / 2, dy: line / 2)).cgPath
            context.addPath(path)
            context.setFillColor(NSColor(Theme.Colors.cardFill).cgColor)
            context.fillPath()
            context.addPath(path)
            context.setStrokeColor(NSColor(Theme.Colors.cardStroke).cgColor)
            context.setLineWidth(line)
            context.strokePath()
        }
    }

    /// Code boxes, headers and find's anchor sit on the drawn layout, which tracks the frame.
    private func layoutOverlays() {
        guard frame.width > 0, let layout = layoutManager, let container = textContainer else {
            return
        }
        layout.ensureLayout(for: container)
        let boxes = (rendered?.codeBlocks ?? []).map { Self.box(of: $0, in: layout) }
        if boxes != codeBoxes {
            codeBoxes = boxes
            needsDisplay = true
        }
        placeHeaders()
        let match = rendered?.current.map { range in
            layout.boundingRect(
                forGlyphRange: layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil),
                in: container)
        }
        guard match != reportedMatch else { return }
        reportedMatch = match
        let report = onCurrentMatch
        // After this pass: state set while SwiftUI lays a view out is dropped with a warning.
        Task { @MainActor in report?(match) }
    }

    /// A block's bounds take in its margin, which is the indent of the list or quote it sits in.
    private static func box(of code: ChatRenderedText.CodeBlock, in layout: NSLayoutManager) -> CGRect {
        let glyphs = layout.glyphRange(forCharacterRange: code.range, actualCharacterRange: nil)
        let bounds = layout.boundsRect(for: code.block, glyphRange: glyphs)
        let margin = { code.block.width(for: .margin, edge: $0) }
        return CGRect(
            x: bounds.minX + margin(.minX), y: bounds.minY + margin(.minY),
            width: bounds.width - margin(.minX) - margin(.maxX),
            height: bounds.height - margin(.minY) - margin(.maxY))
    }

    private func placeHeaders() {
        let blocks = rendered?.codeBlocks ?? []
        while headers.count > blocks.count { headers.removeLast().removeFromSuperview() }
        while headers.count < blocks.count {
            let header = ChatCodeHeader()
            addSubview(header)
            headers.append(header)
        }
        guard let metrics = source?.metrics else { return }
        for (header, (block, box)) in zip(headers, zip(blocks, codeBoxes)) {
            header.show(code: block.code, language: block.language, metrics: metrics)
            let inset = metrics.spacing.xl
            header.frame = CGRect(
                x: box.minX + inset, y: box.minY + metrics.spacing.md,
                width: max(box.width - inset * 2, 0), height: ChatCodeHeader.height)
        }
    }
}

private final class ChatCodeHeader: NSView {
    static var height: CGFloat { ChatMarkdownRenderer.codeHeaderHeight }

    private let label = NSTextField(labelWithString: "")
    private let button = NSButton()
    private var code = ""
    private var reset: Task<Void, Never>?

    init() {
        super.init(frame: .zero)
        label.textColor = NSColor(Theme.Colors.textTertiary)
        label.lineBreakMode = .byTruncatingTail
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.contentTintColor = NSColor(Theme.Colors.textSecondary)
        button.target = self
        button.action = #selector(copyCode)
        addSubview(label)
        addSubview(button)
        showIdle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func resetCursorRects() {
        addCursorRect(visibleRect, cursor: .arrow)
    }

    func show(code: String, language: String?, metrics: InterfaceMetrics) {
        self.code = code
        label.stringValue = language ?? ""
        label.font = metrics.typography.textNSFont(.caption1)
    }

    override func layout() {
        super.layout()
        let side = Self.height
        button.frame = CGRect(x: bounds.width - side, y: 0, width: side, height: side)
        label.frame = CGRect(x: 0, y: 0, width: max(bounds.width - side * 2, 0), height: side)
    }

    private func showIdle() {
        button.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: "Copy Code")
        button.setAccessibilityLabel("Copy Code")
    }

    @objc private func copyCode() {
        Paster.copyPlainText(code)
        button.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Copied")
        button.setAccessibilityLabel("Copied")
        reset?.cancel()
        reset = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Theme.Duration.copyFeedback))
            guard !Task.isCancelled else { return }
            self?.showIdle()
        }
    }
}
