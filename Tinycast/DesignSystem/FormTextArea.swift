import AppKit
import SwiftUI

struct FormTextArea: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: TextSelection?
    @Binding var focused: Bool
    var minimumHeight: CGFloat
    let label: String
    var isCode = false
    /// False for a value that wraps on screen but must stay one line, such as a link.
    var allowsLineBreaks = true
    var moveFocus: (Bool) -> Void
    var insets: NSSize?
    var onCommand: ((Selector) -> Bool)?
    var scrollsHorizontally = false

    @Environment(\.metrics) private var metrics
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSView {
        let view = InputView(usingTextLayoutManager: true)
        view.delegate = context.coordinator
        view.textStorage?.delegate = context.coordinator
        context.coordinator.view = view
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        if isCode {
            view.isAutomaticQuoteSubstitutionEnabled = false
            view.isAutomaticDashSubstitutionEnabled = false
            view.isAutomaticTextReplacementEnabled = false
            view.isAutomaticSpellingCorrectionEnabled = false
        }
        view.string = text
        view.drawsBackground = false
        view.clipsToBounds = true
        view.isVerticallyResizable = true
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.lineFragmentPadding = 0
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.onFocus = { [weak coordinator = context.coordinator] focused in
            guard let coordinator, coordinator.input.focused != focused else { return }
            coordinator.input.focused = focused
        }
        guard scrollsHorizontally else { return view }
        view.isHorizontallyResizable = true
        view.isVerticallyResizable = false
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.size = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.contentView.clipsToBounds = true
        scroll.documentView = view
        return scroll
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.input = self
        guard let view = context.coordinator.view, !context.coordinator.isUpdating else { return }
        context.coordinator.isUpdating = true
        defer { context.coordinator.isUpdating = false }
        let bodyFont = metrics.typography.textNSFont(.body)
        let font =
            isCode
            ? NSFont.monospacedSystemFont(ofSize: bodyFont.pointSize, weight: .regular) : bodyFont
        if view.font != font { view.font = font }
        let color = NSColor(Theme.Colors.textPrimary)
        if view.textColor != color { view.textColor = color }
        if view.insertionPointColor != color { view.insertionPointColor = color }
        let inset = insets ?? NSSize(width: metrics.spacing.xl, height: metrics.spacing.md)
        if view.textContainerInset != inset { view.textContainerInset = inset }
        if view.isEditable != isEnabled { view.isEditable = isEnabled }
        if view.isSelectable != isEnabled { view.isSelectable = isEnabled }
        view.setAccessibilityLabel(label)
        if view.string != text {
            if let storage = view.textStorage {
                let range = NSRange(location: 0, length: storage.length)
                view.breakUndoCoalescing()
                if view.shouldChangeText(in: range, replacementString: text) {
                    storage.replaceCharacters(in: range, with: text)
                    view.didChangeText()
                }
                view.breakUndoCoalescing()
            }
            if let selection, case .selection(let range) = selection.indices {
                view.setSelectedRange(NSRange(range, in: text))
            } else {
                view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            }
        }
        view.wantsFocus = focused
        view.updateFocus()
        if let scroll = nsView as? NSScrollView { fitSingleLine(view, in: scroll) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        guard let view = context.coordinator.view, let width = proposal.width, width > 0 else { return nil }
        if let scroll = nsView as? NSScrollView {
            scroll.setFrameSize(NSSize(width: width, height: minimumHeight))
            fitSingleLine(view, in: scroll)
            return CGSize(width: width, height: minimumHeight)
        }
        view.setFrameSize(NSSize(width: width, height: max(view.frame.height, minimumHeight)))
        var height = view.font.map { $0.ascender - $0.descender + $0.leading } ?? 0
        if let layout = view.textLayoutManager {
            layout.enumerateTextLayoutFragments(
                from: layout.documentRange.endLocation, options: [.reverse, .ensuresLayout]
            ) { fragment in
                height = max(height, fragment.layoutFragmentFrame.maxY)
                return false
            }
        }
        return CGSize(
            width: width, height: max(minimumHeight, ceil(height + view.textContainerInset.height * 2)))
    }

    private func fitSingleLine(_ view: InputView, in scroll: NSScrollView) {
        let width = (view.string as NSString).size(withAttributes: [
            .font: view.font ?? metrics.typography.textNSFont(.body)
        ]).width
        view.minSize = NSSize(width: scroll.contentSize.width, height: minimumHeight)
        view.setFrameSize(
            NSSize(
                width: max(scroll.contentSize.width, ceil(width + view.textContainerInset.width * 2)),
                height: minimumHeight))
        if view.window?.firstResponder === view, view.textStorage?.editedMask.isEmpty == true {
            view.scrollRangeToVisible(view.selectedRange())
        }
    }

    final class InputView: NSTextView {
        var wantsFocus = false
        var onFocus: ((Bool) -> Void)?
        private let editingUndoManager = UndoManager()

        override var undoManager: UndoManager? { editingUndoManager }

        // The non-activating panel cannot rely on the frontmost app's Undo menu.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard window?.firstResponder === self, isEditable, !hasMarkedText(),
                event.charactersIgnoringModifiers?.lowercased() == "z",
                modifiers == .command || modifiers == [.command, .shift]
            else { return super.performKeyEquivalent(with: event) }
            guard !event.isARepeat else { return true }
            breakUndoCoalescing()
            if modifiers == .command {
                editingUndoManager.undo()
            } else {
                editingUndoManager.redo()
            }
            return true
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateFocus()
        }

        func updateFocus() {
            if wantsFocus, isEditable, window?.firstResponder !== self {
                window?.makeFirstResponder(self)
            }
        }

        override func becomeFirstResponder() -> Bool {
            guard super.becomeFirstResponder() else { return false }
            onFocus?(true)
            return true
        }

        override func resignFirstResponder() -> Bool {
            guard super.resignFirstResponder() else { return false }
            onFocus?(false)
            return true
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, @MainActor NSTextStorageDelegate {
        var input: FormTextArea
        var isUpdating = false
        weak var view: InputView?

        init(_ input: FormTextArea) { self.input = input }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let view = notification.object as? NSTextView else { return }
            updateSelection(view)
        }

        func textStorage(
            _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange, changeInLength delta: Int
        ) {
            guard !isUpdating, editedMask.contains(.editedCharacters) else { return }
            isUpdating = true
            defer { isUpdating = false }
            input.text = textStorage.string
            view?.invalidateIntrinsicContentSize()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isUpdating, let view = notification.object as? NSTextView, view.string == input.text
            else { return }
            updateSelection(view)
        }

        private func updateSelection(_ view: NSTextView) {
            guard let range = Range(view.selectedRange(), in: input.text) else { return }
            input.selection = TextSelection(range: range)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if input.onCommand?(commandSelector) == true { return true }
            switch commandSelector {
            case #selector(NSResponder.insertTab(_:)):
                input.moveFocus(false)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                input.moveFocus(true)
                return true
            // ⇥ walks the form's fields, so ⌥⇥ is the way to type a tab.
            case #selector(NSResponder.insertTabIgnoringFieldEditor(_:)):
                textView.insertText("\t", replacementRange: textView.selectedRange())
                return true
            case #selector(NSResponder.insertNewline(_:)),
                #selector(NSResponder.insertLineBreak(_:)),
                #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
                #selector(NSResponder.insertParagraphSeparator(_:)):
                return !input.allowsLineBreaks
            default:
                return false
            }
        }
    }
}
