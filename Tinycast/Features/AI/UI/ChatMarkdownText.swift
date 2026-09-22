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
        view.show(source)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize, nsView view: ChatSelectableTextView, context: Context
    ) -> CGSize? {
        let size = view.fit(width: proposal.width ?? .greatestFiniteMagnitude)
        let rect = view.currentMatchRect
        // After this pass: state set while SwiftUI sizes a view is dropped with a warning.
        Task { @MainActor in onCurrentMatch(rect) }
        return CGSize(width: proposal.width ?? size.width, height: size.height)
    }
}

/// Read-only and backgroundless; it sizes to its text and leaves scrolling to the transcript.
final class ChatSelectableTextView: NSTextView {
    private var source: ChatMarkdownSource?
    private var rendered: ChatRenderedText?
    private var laidOutWidth: CGFloat?
    private var headers: [ChatCodeHeader] = []

    init() {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(
            size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
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
        textStorage?.setAttributedString(output.string)
        laidOutWidth = nil
        if let width = frame.width > 0 ? frame.width : nil { _ = fit(width: width) }
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    func fit(width: CGFloat) -> CGSize {
        guard let container = textContainer, let layout = layoutManager else { return .zero }
        if laidOutWidth != width {
            container.size = CGSize(width: width, height: .greatestFiniteMagnitude)
            laidOutWidth = width
        }
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        placeHeaders()
        return CGSize(width: ceil(used.width), height: ceil(used.height))
    }

    var currentMatchRect: CGRect? {
        guard let range = rendered?.current, let layout = layoutManager, let container = textContainer
        else { return nil }
        let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        return layout.boundingRect(forGlyphRange: glyphs, in: container)
    }

    override func layout() {
        super.layout()
        if bounds.width > 0, laidOutWidth != bounds.width { _ = fit(width: bounds.width) }
    }

    private func placeHeaders() {
        let blocks = rendered?.codeBlocks ?? []
        while headers.count > blocks.count { headers.removeLast().removeFromSuperview() }
        while headers.count < blocks.count {
            let header = ChatCodeHeader()
            addSubview(header)
            headers.append(header)
        }
        guard let layout = layoutManager, let metrics = source?.metrics else { return }
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
