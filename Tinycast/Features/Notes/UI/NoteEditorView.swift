import AppKit
import SwiftUI

struct NoteEditorView: NSViewRepresentable {
    let input: NoteEditorInput
    let rendersMarkdown: Bool
    let onSourceChange: (String) -> Void
    let onCharacterCountChange: (NoteEditorInput, Int) -> Void
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
        Self.configure(textView)
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
            renderer = NoteMarkdownRenderer(isEnabled: parent.rendersMarkdown)
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
        }

        func textDidChange(_ notification: Notification) {
            guard !isInstalling, let textView else { return }
            renderer.sourceDidChange()
            let source = textView.string
            guard source != input.source else { return }
            input = NoteEditorInput(id: input.id, source: source, epoch: input.epoch)
            parent.onSourceChange(source)
            reportCharacterCount()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isInstalling else { return }
            renderer.selectionDidChange()
        }

        /// The `[] ` input rule; returning false drops the typed space the plan already replaced.
        func textView(
            _ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?
        ) -> Bool {
            guard renderer.isEnabled, replacementString == " ", range.length == 0, !textView.hasMarkedText(),
                let noteView = textView as? NoteTextView
            else { return true }
            let plan = NoteMarkdownEditing.plan(
                .typedSpace, source: textView.string, selection: range, markdown: markdown)
            guard let plan else { return true }
            noteView.performEdit(plan)
            return false
        }

        func textView(
            _ textView: NSTextView, shouldChangeTypingAttributes oldTypingAttributes: [String: Any],
            toAttributes newTypingAttributes: [NSAttributedString.Key: Any]
        ) -> [NSAttributedString.Key: Any] {
            renderer.isEnabled ? NoteMarkdownStyler.literal : newTypingAttributes
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let url = link as? URL ?? (link as? String).flatMap { URL(string: $0) }
            guard let url, let scheme = url.scheme?.lowercased(), Self.openableSchemes.contains(scheme) else {
                return true
            }
            if let noteView = textView as? NoteTextView, let event = NSApp.currentEvent,
                let edge = noteView.linkEdge(
                    ofLinkAt: charIndex, clickedAt: noteView.containerPoint(for: event)) {
                textView.setSelectedRange(NSRange(location: edge, length: 0))
                return true
            }
            openURL(url)
            return true
        }

        private static let openableSchemes: Set<String> = ["http", "https", "mailto"]

        var rendersMarkdown: Bool { renderer.isEnabled }

        var markdown: NoteMarkdown { renderer.syncedMarkdown() }

        func focusChanged() {
            renderer.focusDidChange()
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
    }

    static func configure(_ textView: NSTextView) {
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
        textView.font = NoteMarkdownTypography.body
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
        textView.typingAttributes = NoteMarkdownStyler.literal
    }
}
