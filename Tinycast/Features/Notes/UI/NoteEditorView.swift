import AppKit
import SwiftUI

struct NoteEditorView: NSViewRepresentable {
    let input: NoteEditorInput
    let onSourceChange: (String) -> Void
    let onContentHeightChange: (CGFloat) -> Void
    let onReady: (NoteTextView) -> Void
    let onOpenLink: (String) -> Void

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
        textView.editorActions = context.coordinator
        textView.editorUndoManager = context.coordinator.editorUndoManager
        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.install(input, resetUndo: false)
        context.coordinator.reportHeight()
        onReady(textView)
        Task { @MainActor [weak coordinator = context.coordinator] in
            await Task.yield()
            coordinator?.reportHeight()
        }
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
        let presentation = NoteMarkdownParser.parse(source)
        let projection = NoteDisplayProjection.build(
            source: source,
            presentation: presentation,
            activeSourceLocation: nil)
        apply(projection, to: textView)
        return measuredHeight(of: textView)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, NoteTextViewActions {
        var parent: NoteEditorView
        weak var textView: NoteTextView?
        let editorUndoManager = UndoManager()

        private var input: NoteEditorInput
        private var source: String
        private var presentation: NoteMarkdownPresentation
        private var projection: NoteDisplayProjection
        private var sourceSelection = NSRange(location: 0, length: 0)
        private var isApplyingProjection = false
        private var isComposing = false
        private var compositionDisplay = ""
        private var compositionProjection: NoteDisplayProjection?

        private struct DisplayPatch {
            let range: NSRange
            let replacement: String
        }

        init(parent: NoteEditorView) {
            self.parent = parent
            input = parent.input
            source = parent.input.source
            presentation = NoteMarkdownParser.parse(parent.input.source)
            projection = NoteDisplayProjection.build(
                source: parent.input.source,
                presentation: presentation,
                activeSourceLocation: nil)
        }

        func install(_ input: NoteEditorInput, resetUndo: Bool) {
            self.input = input
            source = input.source
            presentation = NoteMarkdownParser.parse(source)
            sourceSelection = NSRange(
                location: min(sourceSelection.location, (source as NSString).length),
                length: 0)
            projection = Signposts.interval("NoteEditor.project") {
                NoteDisplayProjection.build(
                    source: source,
                    presentation: presentation,
                    activeSourceLocation: textView?.window?.firstResponder === textView
                        ? sourceSelection.location : nil)
            }
            if resetUndo { editorUndoManager.removeAllActions() }
            applyProjection()
        }

        func update(_ next: NoteEditorInput) {
            guard next != input else { return }
            let authoritative = next.id != input.id || next.epoch != input.epoch
                || next.source != source
            input = next
            guard authoritative else { return }
            install(next, resetUndo: true)
            reportHeight()
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard !isApplyingProjection else { return true }
            guard !isComposing else { return true }
            let sourceRange = projection.sourceRange(forDisplayRange: affectedCharRange)
            let replacement = replacementString ?? ""
            let selection = NSRange(
                location: sourceRange.location + (replacement as NSString).length,
                length: 0)
            applySourceEdit(
                range: sourceRange,
                replacement: replacement,
                selection: selection,
                actionName: "Typing")
            return false
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingProjection, !isComposing, let textView else { return }
            sourceSelection = projection.sourceRange(forDisplayRange: textView.selectedRange())
            let activeLocation = sourceSelection.length == 0 ? sourceSelection.location : nil
            let next = Signposts.interval("NoteEditor.project") {
                NoteDisplayProjection.build(
                    source: source,
                    presentation: presentation,
                    activeSourceLocation: activeLocation)
            }
            guard next.activeRange != projection.activeRange else { return }
            projection = next
            applyProjection()
            reportHeight()
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingProjection, !isComposing else { return }
        }

        func reportHeight() {
            guard let textView else { return }
            let height = NoteEditorView.measuredHeight(of: textView)
            if textView.frame.height != height {
                textView.setFrameSize(NSSize(width: textView.frame.width, height: height))
            }
            parent.onContentHeightChange(height)
        }

        func noteTextViewCopy(_ textView: NoteTextView) {
            let range = projection.sourceRange(forDisplayRange: textView.selectedRange())
            guard range.length > 0, NSMaxRange(range) <= (source as NSString).length else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString((source as NSString).substring(with: range), forType: .string)
        }

        func noteTextViewCut(_ textView: NoteTextView) {
            let range = projection.sourceRange(forDisplayRange: textView.selectedRange())
            guard range.length > 0 else { return }
            noteTextViewCopy(textView)
            applySourceEdit(
                range: range,
                replacement: "",
                selection: NSRange(location: range.location, length: 0),
                actionName: "Cut")
        }

        func noteTextView(_ textView: NoteTextView, perform command: NoteMarkdownCommand) {
            guard !isComposing,
                let plan = NoteMarkdownEditing.plan(
                    command, source: source, selection: sourceSelection)
            else { return }
            applySourceEdit(
                range: plan.range,
                replacement: plan.replacement,
                selection: plan.selection,
                actionName: "Format")
        }

        func noteTextView(_ textView: NoteTextView, openLinkAt displayLocation: Int) -> Bool {
            guard let link = projection.links.first(where: {
                NSLocationInRange(displayLocation, $0.displayRange)
                    || displayLocation == NSMaxRange($0.displayRange)
            }) else { return false }
            parent.onOpenLink(link.destination)
            return true
        }

        func noteTextViewFocusChanged(_ textView: NoteTextView, isFocused: Bool) {
            guard !isComposing else { return }
            let activeLocation = isFocused && sourceSelection.length == 0
                ? sourceSelection.location : nil
            projection = Signposts.interval("NoteEditor.project") {
                NoteDisplayProjection.build(
                    source: source,
                    presentation: presentation,
                    activeSourceLocation: activeLocation)
            }
            applyProjection()
            reportHeight()
        }

        func noteTextViewWillBeginComposition(_ textView: NoteTextView) {
            guard !isComposing else { return }
            isComposing = true
            compositionDisplay = textView.string
            compositionProjection = projection
        }

        func noteTextViewDidEndComposition(_ textView: NoteTextView) {
            guard isComposing, let originalProjection = compositionProjection else { return }
            isComposing = false
            compositionProjection = nil
            let edit = displayDifference(from: compositionDisplay, to: textView.string)
            guard edit.range.length > 0 || !edit.replacement.isEmpty else {
                applyProjection()
                return
            }
            let sourceRange = originalProjection.sourceRange(forDisplayRange: edit.range)
            applySourceEdit(
                range: sourceRange,
                replacement: edit.replacement,
                selection: NSRange(
                    location: sourceRange.location + (edit.replacement as NSString).length,
                    length: 0),
                actionName: "Typing")
        }

        func toggleTask(sourceRange: NSRange, generation: Int) {
            guard generation == input.epoch, NSMaxRange(sourceRange) <= (source as NSString).length else {
                applyProjection()
                return
            }
            let marker = (source as NSString).substring(with: sourceRange)
            guard marker == "[ ]" || marker == "[x]" || marker == "[X]" else {
                applyProjection()
                return
            }
            applySourceEdit(
                range: NSRange(location: sourceRange.location + 1, length: 1),
                replacement: marker == "[ ]" ? "x" : " ",
                selection: NSRange(location: NSMaxRange(sourceRange), length: 0),
                actionName: "Toggle Task")
            textView?.window?.makeFirstResponder(textView)
        }

        private func applySourceEdit(
            range: NSRange,
            replacement: String,
            selection: NSRange,
            actionName: String,
            registerUndo: Bool = true
        ) {
            let text = source as NSString
            guard range.location != NSNotFound, range.location >= 0, NSMaxRange(range) <= text.length else {
                return
            }
            let oldValue = text.substring(with: range)
            let previousSource = source
            let previousProjection = projection
            let oldSelection = sourceSelection
            let replacementLength = (replacement as NSString).length
            if registerUndo {
                let inverseRange = NSRange(location: range.location, length: replacementLength)
                editorUndoManager.registerUndo(withTarget: self) { target in
                    target.applySourceEdit(
                        range: inverseRange,
                        replacement: oldValue,
                        selection: oldSelection,
                        actionName: actionName)
                }
                editorUndoManager.setActionName(actionName)
            }
            source = text.replacingCharacters(in: range, with: replacement)
            sourceSelection = NSRange(
                location: min(selection.location, (source as NSString).length),
                length: min(selection.length, max(0, (source as NSString).length - selection.location)))
            let result = Signposts.interval("NoteEditor.project") {
                let presentation = NoteMarkdownParser.update(
                    previousSource: previousSource,
                    source: source,
                    presentation: self.presentation,
                    editedRange: range,
                    replacement: replacement)
                let projection = NoteDisplayProjection.build(
                    source: source,
                    presentation: presentation,
                    activeSourceLocation: textView?.window?.firstResponder === textView
                        && sourceSelection.length == 0 ? sourceSelection.location : nil)
                return (presentation, projection)
            }
            presentation = result.0
            projection = result.1
            input = NoteEditorInput(id: input.id, source: source, epoch: input.epoch)
            applyProjection(
                patch: displayPatch(
                    previousSource: previousSource,
                    source: source,
                    previousProjection: previousProjection,
                    projection: projection,
                    editedRange: range,
                    replacement: replacement))
            parent.onSourceChange(source)
            reportHeight()
        }

        private func applyProjection(patch: DisplayPatch? = nil) {
            guard let textView else { return }
            isApplyingProjection = true
            let edit = patch.map { (range: $0.range, replacement: $0.replacement) }
                ?? displayDifference(from: textView.string, to: projection.string)
            if edit.range.length > 0 || !edit.replacement.isEmpty {
                textView.textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
            }
            NoteEditorView.applyAttributes(
                projection,
                to: textView,
                changedDisplayRange: NSRange(
                    location: edit.range.location,
                    length: (edit.replacement as NSString).length))
            let displaySelection = projection.displayRange(forSourceRange: sourceSelection)
            textView.setSelectedRange(displaySelection)
            isApplyingProjection = false
            textView.taskOverlays.update(
                projection.tasks,
                epoch: input.epoch,
                in: textView,
                onToggle: { [weak self] range, generation in
                    self?.toggleTask(sourceRange: range, generation: generation)
                })
        }

        private func displayDifference(from old: String, to new: String)
            -> (range: NSRange, replacement: String)
        {
            let before = old as NSString
            let after = new as NSString
            var prefix = 0
            while prefix < min(before.length, after.length),
                before.character(at: prefix) == after.character(at: prefix)
            {
                prefix += 1
            }
            var suffix = 0
            while suffix < before.length - prefix, suffix < after.length - prefix,
                before.character(at: before.length - suffix - 1)
                    == after.character(at: after.length - suffix - 1)
            {
                suffix += 1
            }
            let oldRange = NSRange(location: prefix, length: before.length - prefix - suffix)
            let replacement = after.substring(
                with: NSRange(location: prefix, length: after.length - prefix - suffix))
            return (oldRange, replacement)
        }

        private func displayPatch(
            previousSource: String,
            source: String,
            previousProjection: NoteDisplayProjection,
            projection: NoteDisplayProjection,
            editedRange: NSRange,
            replacement: String
        ) -> DisplayPatch? {
            let previous = previousSource as NSString
            let current = source as NSString
            let oldValue = previous.substring(with: editedRange)
            guard !replacement.contains(where: { $0.isNewline }),
                !oldValue.contains(where: { $0.isNewline }),
                !replacement.contains("```"), !replacement.contains("~~~"),
                !oldValue.contains("```"), !oldValue.contains("~~~"),
                previous.length > 0, current.length > 0
            else { return nil }
            let oldLocation = min(editedRange.location, previous.length - 1)
            let newLocation = min(editedRange.location, current.length - 1)
            let oldLine = previous.lineRange(for: NSRange(location: oldLocation, length: 0))
            let newLine = current.lineRange(for: NSRange(location: newLocation, length: 0))
            let oldDisplayRange = previousProjection.displayRange(forSourceRange: oldLine)
            let newDisplayRange = projection.displayRange(forSourceRange: newLine)
            let display = projection.string as NSString
            guard NSMaxRange(newDisplayRange) <= display.length else { return nil }
            return DisplayPatch(
                range: oldDisplayRange,
                replacement: display.substring(with: newDisplayRange))
        }
    }

    private static func configure(_ textView: NSTextView) {
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
        textView.allowsUndo = false
        textView.typingAttributes = baseAttributes
    }

    private static let baseAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.preferredFont(forTextStyle: .body),
        .foregroundColor: NSColor(Theme.Colors.noteText)
    ]

    private static func apply(_ projection: NoteDisplayProjection, to textView: NSTextView) {
        textView.string = projection.string
        applyAttributes(projection, to: textView, changedDisplayRange: nil)
    }

    private static func applyAttributes(
        _ projection: NoteDisplayProjection,
        to textView: NSTextView,
        changedDisplayRange: NSRange?
    ) {
        guard let storage = textView.textStorage else { return }
        let range: NSRange
        if let changedDisplayRange, storage.length > 0 {
            let location = min(changedDisplayRange.location, storage.length - 1)
            let length = min(changedDisplayRange.length, storage.length - location)
            range = (storage.string as NSString).lineRange(
                for: NSRange(location: location, length: length))
        } else {
            range = NSRange(location: 0, length: storage.length)
        }
        storage.setAttributes(baseAttributes, range: range)
        for span in projection.styles {
            let intersection = NSIntersectionRange(span.range, range)
            guard intersection.length > 0, NSMaxRange(intersection) <= storage.length else { continue }
            storage.addAttributes(attributes(for: span.style), range: intersection)
        }
    }

    private static func attributes(
        for style: NoteDisplayProjection.Style
    ) -> [NSAttributedString.Key: Any] {
        let body = NSFont.preferredFont(forTextStyle: .body)
        switch style {
        case .heading(let level):
            let textStyle: NSFont.TextStyle = switch level {
            case 1: .title1
            case 2: .title2
            case 3: .title3
            default: .headline
            }
            return [.font: NSFont.preferredFont(forTextStyle: textStyle)]
        case .strong:
            return [.font: NSFontManager.shared.convert(body, toHaveTrait: .boldFontMask)]
        case .emphasis:
            return [.font: NSFontManager.shared.convert(body, toHaveTrait: .italicFontMask)]
        case .strongEmphasis:
            let bold = NSFontManager.shared.convert(body, toHaveTrait: .boldFontMask)
            return [.font: NSFontManager.shared.convert(bold, toHaveTrait: .italicFontMask)]
        case .strikethrough:
            return [.strikethroughStyle: NSUnderlineStyle.single.rawValue]
        case .inlineCode, .codeBlock:
            return [
                .font: NSFont.monospacedSystemFont(ofSize: body.pointSize, weight: .regular),
                .foregroundColor: NSColor(Theme.Colors.noteCode)
            ]
        case .link:
            return [
                .foregroundColor: NSColor(Theme.Colors.noteLink),
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
        case .image, .listMarker, .taskMarker, .horizontalRule, .markup:
            return [.foregroundColor: NSColor(Theme.Colors.noteMarkup)]
        case .blockquote:
            return [
                .font: NSFontManager.shared.convert(body, toHaveTrait: .italicFontMask),
                .foregroundColor: NSColor(Theme.Colors.noteQuote)
            ]
        }
    }

    private static func measuredHeight(of textView: NSTextView) -> CGFloat {
        guard let layoutManager = textView.textLayoutManager,
            let contentManager = layoutManager.textContentManager
        else { return Theme.Size.noteEditorInset * 2 }
        layoutManager.ensureLayout(for: contentManager.documentRange)
        return ceil(
            layoutManager.usageBoundsForTextContainer.height + textView.textContainerInset.height * 2)
    }
}
