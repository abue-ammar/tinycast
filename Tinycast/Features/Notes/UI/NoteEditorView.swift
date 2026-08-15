import AppKit
import SwiftUI

struct NoteEditorView: NSViewRepresentable {
    let input: NoteEditorInput
    let onSourceChange: (String) -> Void
    let onContentHeightChange: (NoteEditorInput, CGFloat) -> Void
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

        let textView = NoteTextView(usingTextLayoutManager: true)
        Self.configure(textView)
        textView.delegate = context.coordinator
        textView.editorUndoManager = context.coordinator.editorUndoManager
        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.install(input, resetUndo: false)
        onReady(textView)
        context.coordinator.scheduleHeightReport(for: input)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(input)
    }

    @MainActor
    static func contentHeight(for source: String, width: CGFloat) -> CGFloat {
        let textView = NoteTextView(usingTextLayoutManager: true)
        configure(textView)
        textView.textContainer?.containerSize = NSSize(
            width: max(0, width - Theme.Size.noteEditorInset * 2),
            height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.setFrameSize(NSSize(width: width, height: 1))
        install(source, in: textView)
        return measuredHeight(of: textView)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteEditorView
        weak var textView: NoteTextView?
        let editorUndoManager = UndoManager()

        private var input: NoteEditorInput
        private var heightReportTask: Task<Void, Never>?
        private var isInstalling = false

        init(parent: NoteEditorView) {
            self.parent = parent
            input = parent.input
        }

        func install(_ input: NoteEditorInput, resetUndo: Bool) {
            guard let textView else { return }
            self.input = input
            let selectionLocation = min(
                textView.selectedRange().location,
                (input.source as NSString).length)
            isInstalling = true
            NoteEditorView.install(input.source, in: textView)
            textView.setSelectedRange(NSRange(location: selectionLocation, length: 0))
            isInstalling = false
            if resetUndo { editorUndoManager.removeAllActions() }
        }

        func update(_ next: NoteEditorInput) {
            guard next != input else { return }
            let authoritative = next.id != input.id || next.epoch != input.epoch
                || next.source != textView?.string
            input = next
            guard authoritative else { return }
            install(next, resetUndo: true)
            scheduleHeightReport(for: next)
        }

        func textDidChange(_ notification: Notification) {
            guard !isInstalling, let textView else { return }
            let source = textView.string
            guard source != input.source else { return }
            input = NoteEditorInput(id: input.id, source: source, epoch: input.epoch)
            parent.onSourceChange(source)
            reportHeight()
            scheduleHeightReport(for: input)
        }

        func reportHeight() {
            guard let textView else { return }
            let height = NoteEditorView.measuredHeight(of: textView)
            if textView.frame.height != height {
                textView.setFrameSize(NSSize(width: textView.frame.width, height: height))
            }
            parent.onContentHeightChange(input, height)
        }

        func scheduleHeightReport(for expectedInput: NoteEditorInput) {
            heightReportTask?.cancel()
            heightReportTask = Task { @MainActor [weak self] in
                await Task.yield()
                guard !Task.isCancelled, let self, matchesCurrentDocument(expectedInput) else {
                    return
                }
                textView?.layoutSubtreeIfNeeded()
                reportHeight()
            }
        }

        func matchesCurrentDocument(_ expectedInput: NoteEditorInput) -> Bool {
            input.id == expectedInput.id && input.epoch == expectedInput.epoch
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
            height: Theme.Size.noteEditorInset)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.font = NSFont.preferredFont(forTextStyle: .body)
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
        textView.typingAttributes = baseAttributes
    }

    private static func install(_ source: String, in textView: NSTextView) {
        textView.string = source
        guard let storage = textView.textStorage, storage.length > 0 else {
            textView.typingAttributes = baseAttributes
            return
        }
        storage.setAttributes(baseAttributes, range: NSRange(location: 0, length: storage.length))
        textView.typingAttributes = baseAttributes
    }

    private static let baseAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.preferredFont(forTextStyle: .body),
        .foregroundColor: NSColor(Theme.Colors.noteText)
    ]

    private static func measuredHeight(of textView: NSTextView) -> CGFloat {
        guard let layoutManager = textView.textLayoutManager,
            let contentManager = layoutManager.textContentManager
        else { return Theme.Size.noteEditorInset * 2 }
        layoutManager.ensureLayout(for: contentManager.documentRange)
        return ceil(
            layoutManager.usageBoundsForTextContainer.height + textView.textContainerInset.height * 2)
    }
}
