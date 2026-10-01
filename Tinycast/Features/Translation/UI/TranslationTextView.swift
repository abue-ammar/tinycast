import AppKit
import SwiftUI

/// One column's native text: the editable source, or the selectable, read-only translation.
struct TranslationTextView: NSViewRepresentable {
    enum Role {
        case source
        case result
    }

    let role: Role
    let text: String
    /// The committed text and whether an input method still holds marked text beside it.
    var onEdit: (String, Bool) -> Void = { _, _ in }
    var onFocusChange: (Bool) -> Void = { _ in }
    let onCopy: () -> Void
    let onMenu: () -> Void

    /// ⇥ / ⇧⇥: the two columns are the whole ring, so either direction lands on the other.
    static func cycleFocus(backwards: Bool) {
        TranslationNativeTextView.cycleFocus(backwards: backwards)
    }

    /// The caret back in the source with its selection intact; another window is left alone.
    static func focusSource(in window: NSWindow?) {
        TranslationNativeTextView.focusSource(in: window)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        // The bars are SwiftUI insets around this view, so AppKit must not inset it a second time.
        scrollView.automaticallyAdjustsContentInsets = false

        let textView = TranslationNativeTextView(usingTextLayoutManager: true)
        textView.role = role
        textView.host = context.coordinator
        textView.delegate = context.coordinator
        Self.setUp(textView)
        Self.applyMetrics(context.environment.metrics, to: textView, isEmpty: text.isEmpty)
        textView.string = text
        textView.frame = scrollView.bounds
        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.lastText = text
        TranslationNativeTextView.register(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        Self.applyMetrics(context.environment.metrics, to: textView, isEmpty: text.isEmpty)
        context.coordinator.apply(text, in: scrollView)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// The Notes editor's plain-text setup; the chat composer's Return-to-send stays its own.
    private static func setUp(_ textView: TranslationNativeTextView) {
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.allowsUndo = true
        textView.applyColors()
    }

    /// Re-applied on every update: only a changed value is written, so the caret never resets.
    private static func applyMetrics(
        _ metrics: InterfaceMetrics, to textView: TranslationNativeTextView, isEmpty: Bool
    ) {
        let showsPlaceholder = textView.role == .source && isEmpty && !textView.hasMarkedText()
        let font = showsPlaceholder
            ? metrics.typography.searchFieldNSFont : metrics.typography.textNSFont(.body)
        if textView.font != font { textView.font = font }
        let inset = NSSize(width: metrics.spacing.xxl, height: metrics.spacing.xxl)
        if textView.textContainerInset != inset { textView.textContainerInset = inset }
        let editable = textView.role == .source
        if textView.isEditable != editable { textView.isEditable = editable }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TranslationTextView
        weak var textView: TranslationNativeTextView?
        /// The committed text both sides last agreed on; only an outside change diverges from it.
        var lastText = ""
        private var lastComposing = false
        private var isApplying = false

        init(parent: TranslationTextView) {
            self.parent = parent
        }

        /// An outside write: swap, clear, a new result. Edits echo back equal and never land here.
        func apply(_ text: String, in scrollView: NSScrollView) {
            guard text != lastText, let textView else { return }
            lastText = text
            guard textView.string != text else { return }
            isApplying = true
            if textView.hasMarkedText() {
                textView.inputContext?.discardMarkedText()
                textView.unmarkText()
            }
            textView.string = text
            textView.undoManager?.removeAllActions()
            isApplying = false
            switch parent.role {
            case .source:
                textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            case .result:
                textView.setSelectedRange(NSRange(location: 0, length: 0))
                scrollView.contentView.scroll(to: .zero)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
            // The write ended any composition, which the owner only learns of from here.
            if lastComposing {
                lastComposing = false
                parent.onEdit(text, false)
            }
        }

        func detach() {
            guard let textView else { return }
            TranslationNativeTextView.unregister(textView)
            textView.host = nil
            textView.delegate = nil
            self.textView = nil
            parent.onFocusChange(false)
        }

        func focusChanged(_ focused: Bool) {
            parent.onFocusChange(focused)
        }

        func copyTranslation() { parent.onCopy() }

        func openMenu() { parent.onMenu() }

        func textDidChange(_ notification: Notification) {
            report()
        }

        /// Marked text announces itself through the selection, before any committed text changes.
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView, textView.hasMarkedText() != lastComposing else { return }
            report()
        }

        private func report(settled: Bool = false) {
            guard !isApplying, let textView else { return }
            // Marked text is inserted before its range is recorded; read it once both are there.
            if !settled, textView.hasMarkedText(), textView.markedRange().length == 0 {
                Task { @MainActor [weak self] in self?.report(settled: true) }
                return
            }
            let composing = textView.hasMarkedText()
            let committed = textView.committedText
            guard composing != lastComposing || committed != lastText else { return }
            lastComposing = composing
            lastText = committed
            parent.onEdit(committed, composing)
        }
    }
}
