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
        private var revealedSelectionLocation: Int?

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
            revealedSelectionLocation = nil
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
            revealedSelectionLocation = nil
            let sourceRange = projection.sourceRange(
                forReplacingDisplayRange: affectedCharRange)
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
            revealedSelectionLocation = nil
            sourceSelection = projection.sourceRange(forDisplayRange: textView.selectedRange())
            guard sourceSelection.length == 0 else { return }
            let next = Signposts.interval("NoteEditor.project") {
                NoteDisplayProjection.build(
                    source: source,
                    presentation: presentation,
                    activeSourceLocation: sourceSelection.location)
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
            let range = projection.sourceRange(
                forCopyingDisplayRange: textView.selectedRange())
            guard range.length > 0, NSMaxRange(range) <= (source as NSString).length else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString((source as NSString).substring(with: range), forType: .string)
        }

        func noteTextViewCut(_ textView: NoteTextView) {
            let range = projection.sourceRange(
                forCopyingDisplayRange: textView.selectedRange())
            guard range.length > 0 else { return }
            noteTextViewCopy(textView)
            applySourceEdit(
                range: range,
                replacement: "",
                selection: NSRange(location: range.location, length: 0),
                actionName: "Cut")
        }

        func noteTextView(_ textView: NoteTextView, perform command: NoteMarkdownCommand) {
            let formattingSelection = sourceSelection.length == 0
                ? sourceSelection
                : projection.sourceRange(
                    forCopyingDisplayRange: textView.selectedRange())
            guard !isComposing,
                let plan = NoteMarkdownEditing.plan(
                    command,
                    source: source,
                    selection: formattingSelection,
                    presentation: presentation)
            else { return }
            revealedSelectionLocation = command == .link ? plan.selection.location : nil
            guard plan.changesSource else {
                selectSourceRange(plan.selection, reveal: true)
                return
            }
            applySourceEdit(
                range: plan.range,
                replacement: plan.replacement,
                selection: plan.selection,
                actionName: "Format")
        }

        func noteTextViewFormattingState(_ textView: NoteTextView) -> Set<NoteMarkdownCommand> {
            NoteMarkdownEditing.activeCommands(
                selection: sourceSelection,
                source: source,
                presentation: presentation)
        }

        func noteTextView(
            _ textView: NoteTextView,
            performListEdit action: NoteListEditingAction
        ) -> Bool {
            guard !isComposing,
                let plan = NoteMarkdownEditing.planListEdit(
                    action,
                    source: source,
                    selection: sourceSelection)
            else { return false }
            revealedSelectionLocation = nil
            applySourceEdit(
                range: plan.range,
                replacement: plan.replacement,
                selection: plan.selection,
                actionName: "Edit List")
            return true
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
            if !isFocused { revealedSelectionLocation = nil }
            let activeLocation = isFocused
                ? revealedSelectionLocation
                    ?? (sourceSelection.length == 0 ? sourceSelection.location : nil)
                : nil
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
                    activeSourceLocation: revealedSelectionLocation
                        ?? (textView?.window?.firstResponder === textView
                            && sourceSelection.length == 0 ? sourceSelection.location : nil))
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

        private func selectSourceRange(_ range: NSRange, reveal: Bool) {
            let length = (source as NSString).length
            sourceSelection = NSRange(
                location: min(max(0, range.location), length),
                length: min(range.length, max(0, length - range.location)))
            revealedSelectionLocation = reveal ? sourceSelection.location : nil
            projection = Signposts.interval("NoteEditor.project") {
                NoteDisplayProjection.build(
                    source: source,
                    presentation: presentation,
                    activeSourceLocation: revealedSelectionLocation)
            }
            applyProjection()
            reportHeight()
        }

        private func applyProjection(patch: DisplayPatch? = nil) {
            guard let textView else { return }
            let caretScreenY = visibleCaretScreenY(in: textView)
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
            if textView.selectedRange() != displaySelection {
                textView.setSelectedRange(displaySelection)
            }
            isApplyingProjection = false
            if caretScreenY != nil {
                let contentHeight = NoteEditorView.measuredHeight(of: textView)
                if textView.frame.height != contentHeight {
                    textView.setFrameSize(NSSize(width: textView.frame.width, height: contentHeight))
                }
            }
            restoreVisibleCaret(caretScreenY, selection: displaySelection, in: textView)
            textView.taskOverlays.update(
                projection.tasks,
                epoch: input.epoch,
                in: textView,
                onToggle: { [weak self] range, generation in
                    self?.toggleTask(sourceRange: range, generation: generation)
                })
        }

        private func visibleCaretScreenY(in textView: NoteTextView) -> CGFloat? {
            guard textView.window?.firstResponder === textView,
                sourceSelection.length == 0
            else { return nil }
            let caret = NSRange(location: NSMaxRange(textView.selectedRange()), length: 0)
            let rect = textView.firstRect(forCharacterRange: caret, actualRange: nil)
            return rect.height > 0 ? rect.midY : nil
        }

        private func restoreVisibleCaret(
            _ previousScreenY: CGFloat?,
            selection: NSRange,
            in textView: NoteTextView
        ) {
            guard let previousScreenY, let scrollView = textView.enclosingScrollView else { return }
            if let layoutManager = textView.textLayoutManager,
                let contentManager = layoutManager.textContentManager
            {
                layoutManager.ensureLayout(for: contentManager.documentRange)
            }
            scrollView.layoutSubtreeIfNeeded()
            textView.scrollRangeToVisible(selection)
            let caret = NSRange(location: NSMaxRange(selection), length: 0)
            let rect = textView.firstRect(forCharacterRange: caret, actualRange: nil)
            guard rect.height > 0 else { return }
            let clipView = scrollView.contentView
            let maximumY = max(0, textView.bounds.height - clipView.bounds.height)
            let adjustedY = min(
                maximumY,
                max(0, clipView.bounds.origin.y + previousScreenY - rect.midY))
            clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: adjustedY))
            scrollView.reflectScrolledClipView(clipView)
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
            apply(span.style, to: storage, range: intersection)
        }
    }

    private static func apply(
        _ style: NoteDisplayProjection.Style,
        to storage: NSTextStorage,
        range: NSRange
    ) {
        switch style {
        case .heading(let level):
            let textStyle: NSFont.TextStyle = switch level {
            case 1: .title1
            case 2: .title2
            case 3: .title3
            case 4: .headline
            case 5: .subheadline
            default: .caption1
            }
            let font = NSFont.preferredFont(forTextStyle: textStyle)
            storage.addAttribute(
                .font,
                value: level >= 5
                    ? NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                    : font,
                range: range)
            applyParagraphStyle(to: storage, range: range) { paragraph in
                paragraph.paragraphSpacingBefore = Theme.Spacing.sm
                paragraph.paragraphSpacing = Theme.Spacing.xs
            }
        case .strong:
            applyFontTrait(.boldFontMask, to: storage, range: range)
        case .emphasis:
            applyFontTrait(.italicFontMask, to: storage, range: range)
        case .strongEmphasis:
            applyFontTrait([.boldFontMask, .italicFontMask], to: storage, range: range)
        case .strikethrough:
            storage.addAttribute(
                .strikethroughStyle,
                value: NSUnderlineStyle.single.rawValue,
                range: range)
        case .inlineCode:
            applyMonospacedFont(to: storage, range: range)
            storage.addAttribute(
                .foregroundColor,
                value: NSColor(Theme.Colors.noteCode),
                range: range)
        case .codeBlock:
            applyMonospacedFont(to: storage, range: range)
            storage.addAttribute(
                .foregroundColor,
                value: NSColor(Theme.Colors.noteCode),
                range: range)
            applyTextBlock(codeBlock(), to: storage, range: range)
        case .link:
            storage.addAttributes(
                [
                    .foregroundColor: NSColor(Theme.Colors.noteLink),
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ],
                range: range)
        case .image, .markup:
            storage.addAttribute(
                .foregroundColor,
                value: NSColor(Theme.Colors.noteMarkup),
                range: range)
        case .listMarker, .taskMarker:
            storage.addAttribute(
                .foregroundColor,
                value: NSColor(Theme.Colors.noteMarkup),
                range: range)
            applyParagraphStyle(to: storage, range: range) { paragraph in
                paragraph.firstLineHeadIndent = 0
                paragraph.headIndent = Theme.Spacing.xxl
            }
        case .horizontalRule:
            storage.addAttribute(
                .foregroundColor,
                value: NSColor.clear,
                range: range)
            applyTextBlock(horizontalRuleBlock(), to: storage, range: range)
        case .blockquote:
            applyFontTrait(.italicFontMask, to: storage, range: range)
            storage.addAttribute(
                .foregroundColor,
                value: NSColor(Theme.Colors.noteQuote),
                range: range)
            applyTextBlock(blockquoteBlock(), to: storage, range: range)
        }
    }

    private static func applyFontTrait(
        _ trait: NSFontTraitMask,
        to storage: NSTextStorage,
        range: NSRange
    ) {
        storage.enumerateAttribute(.font, in: range) { value, effectiveRange, _ in
            let font = value as? NSFont ?? NSFont.preferredFont(forTextStyle: .body)
            storage.addAttribute(
                .font,
                value: NSFontManager.shared.convert(font, toHaveTrait: trait),
                range: effectiveRange)
        }
    }

    private static func applyMonospacedFont(
        to storage: NSTextStorage,
        range: NSRange
    ) {
        storage.enumerateAttribute(.font, in: range) { value, effectiveRange, _ in
            let font = value as? NSFont ?? NSFont.preferredFont(forTextStyle: .body)
            storage.addAttribute(
                .font,
                value: NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular),
                range: effectiveRange)
        }
    }

    private static func applyParagraphStyle(
        to storage: NSTextStorage,
        range: NSRange,
        update: (NSMutableParagraphStyle) -> Void
    ) {
        let paragraphRange = (storage.string as NSString).paragraphRange(for: range)
        var runs: [(NSRange, NSMutableParagraphStyle)] = []
        storage.enumerateAttribute(.paragraphStyle, in: paragraphRange) { value, effectiveRange, _ in
            let paragraph = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                ?? NSMutableParagraphStyle()
            update(paragraph)
            runs.append((effectiveRange, paragraph))
        }
        if runs.isEmpty {
            let paragraph = NSMutableParagraphStyle()
            update(paragraph)
            runs.append((paragraphRange, paragraph))
        }
        for (effectiveRange, paragraph) in runs {
            storage.addAttribute(.paragraphStyle, value: paragraph, range: effectiveRange)
        }
    }

    private static func applyTextBlock(
        _ block: NSTextBlock,
        to storage: NSTextStorage,
        range: NSRange
    ) {
        applyParagraphStyle(to: storage, range: range) { paragraph in
            paragraph.textBlocks.append(block)
        }
    }

    private static func blockquoteBlock() -> NSTextBlock {
        let block = NSTextBlock()
        block.setWidth(
            Theme.Spacing.xxs,
            type: .absoluteValueType,
            for: .border,
            edge: .minX)
        block.setBorderColor(NSColor(Theme.Colors.noteQuote), for: .minX)
        block.setWidth(
            Theme.Spacing.lg,
            type: .absoluteValueType,
            for: .padding,
            edge: .minX)
        return block
    }

    private static func codeBlock() -> NSTextBlock {
        let block = NSTextBlock()
        block.backgroundColor = NSColor(Theme.Colors.cardFill)
        block.setWidth(Theme.Spacing.md, type: .absoluteValueType, for: .padding)
        block.setWidth(Theme.Spacing.xs, type: .absoluteValueType, for: .margin)
        return block
    }

    private static func horizontalRuleBlock() -> NSTextBlock {
        let block = NSTextBlock()
        block.setContentWidth(100, type: .percentageValueType)
        block.setWidth(
            1,
            type: .absoluteValueType,
            for: .border,
            edge: .minY)
        block.setBorderColor(NSColor(Theme.Colors.noteMarkup), for: .minY)
        block.setWidth(
            Theme.Spacing.md,
            type: .absoluteValueType,
            for: .padding,
            edge: .minY)
        block.setWidth(
            Theme.Spacing.md,
            type: .absoluteValueType,
            for: .padding,
            edge: .maxY)
        return block
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
