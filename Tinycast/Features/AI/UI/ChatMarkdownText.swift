import AppKit
import SwiftUI

/// One AppKit text view per segment, since SwiftUI's `Text` selects only within one paragraph.
struct ChatMarkdownText: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.chatTextHighlight) private var highlight
    @Environment(\.chatCitations) private var citations
    @Environment(\.chatFindPath) private var path
    let blocks: [MarkdownBlock]
    var failed = false

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
                failed: failed, metrics: metrics)
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

    /// AppKit's own designated initializer; `NSTextView(frame:)` routes through it.
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

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutOverlays()
    }

    /// The code headers and find's anchor sit on the drawn layout, which tracks the frame.
    private func layoutOverlays() {
        guard frame.width > 0, let layout = layoutManager, let container = textContainer else {
            return
        }
        layout.ensureLayout(for: container)
        placeHeaders(in: layout)
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

    private func placeHeaders(in layout: NSLayoutManager) {
        let blocks = rendered?.codeBlocks ?? []
        while headers.count > blocks.count { headers.removeLast().removeFromSuperview() }
        while headers.count < blocks.count {
            let header = ChatCodeHeader()
            addSubview(header)
            headers.append(header)
        }
        guard let metrics = source?.metrics else { return }
        for (header, block) in zip(headers, blocks) {
            header.show(code: block.code, language: block.language, metrics: metrics)
            let glyphs = layout.glyphRange(forCharacterRange: block.range, actualCharacterRange: nil)
            let box = layout.boundsRect(for: block.block, glyphRange: glyphs)
            let inset = metrics.spacing.xl
            header.frame = CGRect(
                x: box.minX + inset, y: box.minY + metrics.spacing.md,
                width: max(box.width - inset * 2, 0), height: ChatCodeHeader.height)
        }
    }
}

/// A code block's language and its own Copy, in the strip its text block leaves above the code.
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
