import AppKit
import SwiftUI

struct NoteEditorView: NSViewRepresentable {
    let input: NoteEditorInput
    let rendersMarkdown: Bool
    var typography = NoteMarkdownTypography.system
    let onSourceChange: (String) -> Void
    let onCharacterCountChange: (NoteEditorInput, Int) -> Void
    let onFormattingChange: (NoteEditorInput, NoteFormatting) -> Void
    let onReady: (NoteTextView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        // `NotesView` lays out its own title-bar band, so AppKit must not inset this a second time.
        scrollView.automaticallyAdjustsContentInsets = false

        let textView = NoteTextView(usingTextLayoutManager: true)
        Self.configure(textView, typography: typography)
        textView.delegate = context.coordinator
        textView.editorUndoManager = context.coordinator.editorUndoManager
        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.install(input, resetUndo: false)
        onReady(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(input)
        context.coordinator.setRendersMarkdown(rendersMarkdown)
        context.coordinator.setTypography(typography)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, NoteTextViewEditing {
        var parent: NoteEditorView
        weak var textView: NoteTextView? {
            didSet { attach() }
        }
        let editorUndoManager = UndoManager()
        let renderer: NoteMarkdownRenderer
        /// Replaced by the harness, which records a link instead of opening a browser.
        var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }

        private var input: NoteEditorInput
        private var isInstalling = false
        /// Held here because the layout manager keeps its delegate weakly.
        private let fragmentProvider = NoteLayoutFragmentProvider()

        init(parent: NoteEditorView) {
            self.parent = parent
            input = parent.input
            renderer = NoteMarkdownRenderer(
                isEnabled: parent.rendersMarkdown, typography: parent.typography)
        }

        private func attach() {
            renderer.textView = textView
            textView?.editing = self
            textView?.textLayoutManager?.delegate = fragmentProvider
        }

        func install(_ input: NoteEditorInput, resetUndo: Bool) {
            guard let textView else { return }
            self.input = input
            let selectionLocation = min(
                textView.selectedRange().location,
                (input.source as NSString).length)
            isInstalling = true
            textView.string = input.source
            textView.setSelectedRange(NSRange(location: selectionLocation, length: 0))
            renderer.reset()
            isInstalling = false
            if resetUndo { editorUndoManager.removeAllActions() }
            reportCharacterCount()
            reportFormatting()
        }

        func update(_ next: NoteEditorInput) {
            guard next != input else { return }
            let authoritative =
                next.id != input.id || next.epoch != input.epoch
                || next.source != textView?.string
            input = next
            guard authoritative else { return }
            install(next, resetUndo: true)
        }

        func setRendersMarkdown(_ rendersMarkdown: Bool) {
            guard rendersMarkdown != renderer.isEnabled else { return }
            renderer.isEnabled = rendersMarkdown
            renderer.reset()
            reportFormatting()
        }

        func setTypography(_ typography: NoteMarkdownTypography) {
            guard typography.fontFamily != renderer.typography.fontFamily else { return }
            renderer.typography = typography
            textView?.font = typography.body
            renderer.reset()
        }

        func textDidChange(_ notification: Notification) {
            guard !isInstalling, let textView else { return }
            renderer.sourceDidChange()
            reportFormatting()
            let source = textView.string
            guard source != input.source else { return }
            input = NoteEditorInput(id: input.id, source: source, epoch: input.epoch)
            parent.onSourceChange(source)
            reportCharacterCount()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isInstalling else { return }
            renderer.selectionDidChange()
            reportFormatting()
        }

        func textView(
            _ textView: NSTextView, shouldChangeTypingAttributes oldTypingAttributes: [String: Any],
            toAttributes newTypingAttributes: [NSAttributedString.Key: Any]
        ) -> [NSAttributedString.Key: Any] {
            renderer.isEnabled
                ? NoteMarkdownStyler.literal(renderer.typography) : newTypingAttributes
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let url = link as? URL ?? (link as? String).flatMap { URL(string: $0) }
            guard let url, let scheme = url.scheme?.lowercased(),
                NoteMarkdownStyler.openableSchemes.contains(scheme)
            else {
                return true
            }
            if let noteView = textView as? NoteTextView, let event = NSApp.currentEvent,
                let edge = noteView.linkEdge(
                    ofLinkAt: charIndex, clickedAt: noteView.containerPoint(for: event))
            {
                textView.setSelectedRange(NSRange(location: edge, length: 0))
                return true
            }
            openURL(url)
            return true
        }

        var rendersMarkdown: Bool { renderer.isEnabled }

        var markdown: NoteMarkdown { renderer.syncedMarkdown() }

        func focusChanged() {
            renderer.selectionDidChange()
        }

        func appearanceChanged() {
            renderer.reset()
        }

        func dragSelectionEnded() {
            renderer.selectionDidChange()
        }

        /// `NSTextStorage.length` is maintained by TextKit, so the counter costs nothing per edit.
        private func reportCharacterCount() {
            parent.onCharacterCountChange(input, textView?.textStorage?.length ?? 0)
        }

        /// With rendering off there is no parse to read, and the bar is hidden anyway.
        private func reportFormatting() {
            guard let textView else { return }
            let formatting =
                renderer.isEnabled
                ? NoteMarkdownEditing.formatting(
                    source: textView.string, selection: textView.selectedRange(), markdown: markdown)
                : .plain
            parent.onFormattingChange(input, formatting)
        }
    }

    static func configure(_ textView: NSTextView, typography: NoteMarkdownTypography) {
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(
            width: Theme.Size.noteEditorInset,
            height: Theme.Size.noteEditorTopInset)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.font = typography.body
        textView.textColor = NSColor(Theme.Colors.noteText)
        textView.insertionPointColor = NSColor(Theme.Colors.noteText)
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor(Theme.Colors.selection),
            .foregroundColor: NSColor(Theme.Colors.noteText)
        ]
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.usesFindPanel = true
        textView.allowsUndo = true
        textView.linkTextAttributes = [.foregroundColor: NSColor.linkColor, .cursor: NSCursor.pointingHand]
        textView.typingAttributes = NoteMarkdownStyler.literal(typography)
    }
}
