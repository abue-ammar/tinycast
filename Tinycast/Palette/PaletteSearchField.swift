import AppKit
import SwiftUI

/// Keys an `NSTextView` would consume before the palette could answer them.
enum PaletteSearchKey {
    case up
    case down
    case left
    case right
    case submit
    case tab
    case cancel
}

/// The palette's search field. One `NSTextView` draws both the query and the placeholder, so
/// nothing steps when focus moves. docs/features/palette.md#the-search-field-is-tinycasts
struct PaletteSearchField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let prompt: String
    /// Runs on every update the field holds focus for, not only on the move into focus.
    let onFocused: (NSTextInputContext) -> Void
    /// `true` keeps the key; `false` leaves it to the caret.
    let onKeyCommand: (PaletteSearchKey, NSEvent.ModifierFlags) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
        scrollView.borderType = .noBorder
        // The header lays out its own metrics; AppKit must not inset the field a second time.
        scrollView.automaticallyAdjustsContentInsets = false

        let coordinator = context.coordinator
        let textView = PaletteSearchTextView()
        Self.configure(textView)
        textView.delegate = coordinator
        textView.onKeyCommand = onKeyCommand
        textView.onFocusChange = { [weak coordinator] in coordinator?.report(focus: $0) }
        textView.placeholder = prompt
        textView.setAccessibilityLabel(prompt)
        textView.string = text
        scrollView.documentView = textView
        coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        textView.onKeyCommand = onKeyCommand
        if textView.placeholder != prompt {
            textView.placeholder = prompt
            textView.setAccessibilityLabel(prompt)
            textView.needsDisplay = true
        }
        // Replacing the storage mid-composition would drop the marked text the IME still owns.
        if textView.string != text, !textView.hasMarkedText() {
            textView.replaceWholeString(with: text)
        }
        guard isFocused else { return }
        if textView.window?.firstResponder !== textView {
            guard textView.window?.makeFirstResponder(textView) == true else { return }
        }
        if let inputContext = textView.inputContext { onFocused(inputContext) }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PaletteSearchField
        weak var textView: PaletteSearchTextView?

        init(parent: PaletteSearchField) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? PaletteSearchTextView else { return }
            textView.needsDisplay = true
            // An IME owns the marked text until it commits; publishing it would search the pinyin.
            guard !textView.hasMarkedText(), textView.string != parent.text else { return }
            parent.text = textView.string
        }

        /// Deferred: AppKit swaps first responder inside a SwiftUI update, and this writes state.
        func report(focus: Bool) {
            Task { @MainActor in
                guard self.parent.isFocused != focus else { return }
                self.parent.isFocused = focus
            }
        }
    }

    /// What AppKit's own field editor pads by: the caret is centred on the insertion point, so
    /// column 0 loses half of it to the clip view without this.
    private static let fieldEditorPadding: CGFloat = 2

    private static func configure(_ textView: PaletteSearchTextView) {
        textView.isFieldEditor = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.height]
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.size = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = fieldEditorPadding
        textView.font = Theme.Typography.searchFieldNSFont
        textView.textColor = NSColor(Theme.Colors.textPrimary)
        textView.insertionPointColor = NSColor(Theme.Colors.textPrimary)
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor(Theme.Colors.selection),
            .foregroundColor: NSColor(Theme.Colors.textPrimary)
        ]
        // A query is matched literally, so nothing may rewrite what was typed.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.usesFindPanel = false
        textView.allowsUndo = true
        textView.setAccessibilityRole(.textField)
    }
}

/// Draws its own placeholder through the same text container as the query, so the two share an
/// origin no focus change can move. There is no cell to hand the string to and no field editor to
/// take it back — that swap is what stepped the placeholder a point.
@MainActor
final class PaletteSearchTextView: NSTextView {
    var placeholder = ""
    var onKeyCommand: ((PaletteSearchKey, NSEvent.ModifierFlags) -> Bool)?
    var onFocusChange: ((Bool) -> Void)?

    /// `doCommand(by:)` names the action but not the chord that produced it.
    private var currentModifiers: NSEvent.ModifierFlags = []

    func replaceWholeString(with next: String) {
        string = next
        setSelectedRange(NSRange(location: (next as NSString).length, length: 0))
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        currentModifiers = event.modifierFlags
        super.keyDown(with: event)
    }

    override func doCommand(by selector: Selector) {
        if let key = Self.paletteKey(for: selector),
            onKeyCommand?(key, currentModifiers) == true
        {
            return
        }
        super.doCommand(by: selector)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChange?(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onFocusChange?(false) }
        return resigned
    }

    override func layout() {
        super.layout()
        matchWidthToClipView()
        centerLineVertically()
    }

    /// Never narrower than its clip view, so a click past the last glyph still lands the caret.
    private func matchWidthToClipView() {
        guard let clip = enclosingScrollView?.contentView else { return }
        minSize = NSSize(width: clip.bounds.width, height: 0)
        guard bounds.width < clip.bounds.width else { return }
        setFrameSize(NSSize(width: clip.bounds.width, height: bounds.height))
    }

    /// The field fills the header row, so the single line is centred by inset rather than by frame.
    private func centerLineVertically() {
        let inset = max(0, ((bounds.height - lineHeight) / 2).rounded())
        guard textContainerInset.height != inset else { return }
        textContainerInset = NSSize(width: 0, height: inset)
    }

    /// Before `super`, so the caret still draws over the placeholder rather than under it.
    override func draw(_ dirtyRect: NSRect) {
        drawPlaceholder()
        super.draw(dirtyRect)
    }

    private func drawPlaceholder() {
        guard string.isEmpty, !hasMarkedText(), !placeholder.isEmpty, let font else { return }
        // The origin TextKit gives the first glyph, so placeholder and query cannot disagree.
        let origin = NSPoint(
            x: textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 0),
            y: textContainerOrigin.y)
        NSAttributedString(
            string: placeholder,
            attributes: [
                .font: font,
                .foregroundColor: NSColor(Theme.Colors.textTertiary)
            ]
        ).draw(at: origin)
    }

    private var lineHeight: CGFloat {
        guard let font else { return 0 }
        return ceil(font.ascender - font.descender + font.leading)
    }

    private static func paletteKey(for selector: Selector) -> PaletteSearchKey? {
        switch selector {
        case #selector(NSResponder.moveUp(_:)),
            #selector(NSResponder.moveUpAndModifySelection(_:)),
            #selector(NSResponder.moveToBeginningOfDocument(_:)):
            return .up
        case #selector(NSResponder.moveDown(_:)),
            #selector(NSResponder.moveDownAndModifySelection(_:)),
            #selector(NSResponder.moveToEndOfDocument(_:)):
            return .down
        case #selector(NSResponder.moveLeft(_:)),
            #selector(NSResponder.moveLeftAndModifySelection(_:)):
            return .left
        case #selector(NSResponder.moveRight(_:)),
            #selector(NSResponder.moveRightAndModifySelection(_:)):
            return .right
        case #selector(NSResponder.insertNewline(_:)),
            #selector(NSResponder.insertLineBreak(_:)),
            #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            return .submit
        case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
            return .tab
        case #selector(NSResponder.cancelOperation(_:)):
            return .cancel
        default:
            return nil
        }
    }
}
