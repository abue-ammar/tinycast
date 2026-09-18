import AppKit

@MainActor
final class NoteTextView: NSTextView, InjectableTextView {
    var editorUndoManager: UndoManager?
    weak var editing: NoteTextViewEditing?
    /// True during `mouseDown`'s drag loop; revealing mid-drag would shift text under the pointer.
    private(set) var isDragSelecting = false

    /// Tracked here because the window still names this view first responder while it resigns.
    private var isFirstResponder = false
    private var keyObservers: [NotificationToken] = []

    private static let checkboxSlop: CGFloat = 3

    override var undoManager: UndoManager? { editorUndoManager }

    var isFocused: Bool { isFirstResponder && window?.isKeyWindow == true }

    private var rendersMarkdown: Bool { editing?.rendersMarkdown == true }

    /// One undoable replacement that reaches `textDidChange`, so autosave and restyling see it.
    func performEdit(_ plan: NoteEditPlan) {
        breakUndoCoalescing()
        guard shouldChangeText(in: plan.range, replacementString: plan.replacement) else { return }
        textStorage?.replaceCharacters(in: plan.range, with: plan.replacement)
        didChangeText()
        setSelectedRange(plan.selection)
        breakUndoCoalescing()
    }

    /// The formatting bar's way in: the same plan, gate and undo step as the matching chord.
    func format(_ action: NoteEditAction) {
        perform(action)
    }

    // MARK: - Keys

    override func insertNewline(_ sender: Any?) {
        guard !perform(.newline) else { return }
        super.insertNewline(sender)
    }

    override func deleteBackward(_ sender: Any?) {
        guard !perform(.deleteBackward) else { return }
        super.deleteBackward(sender)
    }

    /// The `[] ` input rule; the plan writes the space itself, so the typed one is dropped.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        let caret = selectedRange()
        if string as? String == " ", caret.length == 0,
            replacementRange.location == NSNotFound || replacementRange == caret,
            perform(.typedSpace) {
            return
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    override func insertTab(_ sender: Any?) {
        guard !perform(.indent) else { return }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        guard !perform(.outdent) else { return }
        super.insertBacktab(sender)
    }

    /// A formatting chord is always ours while rendering, even when it has nothing to do.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard rendersMarkdown, window?.firstResponder === self, let action = Self.chord(for: event) else {
            return super.performKeyEquivalent(with: event)
        }
        if !event.isARepeat { perform(action) }
        return true
    }

    override func paste(_ sender: Any?) {
        guard !pasteLink(from: .general) else { return }
        super.paste(sender)
    }

    /// Pasting a lone URL over selected text makes a link; anything else pastes as plain text.
    func pasteLink(from pasteboard: NSPasteboard) -> Bool {
        guard let string = pasteboard.string(forType: .string) else { return false }
        return perform(.pasteURL(string))
    }

    @discardableResult
    private func perform(_ action: NoteEditAction) -> Bool {
        guard let editing, editing.rendersMarkdown, !hasMarkedText() else { return false }
        let plan = NoteMarkdownEditing.plan(
            action, source: string, selection: selectedRange(), markdown: editing.markdown)
        guard let plan else { return false }
        performEdit(plan)
        return true
    }

    /// The digit key codes, stated here so a local chord needs no Carbon.
    private enum DigitKey {
        static let zero: UInt16 = 0x1D
        static let one: UInt16 = 0x12
        static let two: UInt16 = 0x13
        static let three: UInt16 = 0x14
        static let seven: UInt16 = 0x1A
        static let eight: UInt16 = 0x1C
        static let nine: UInt16 = 0x19
    }

    /// Digits match by key code, since shifted and optioned digits vary by keyboard layout.
    private static func chord(for event: NSEvent) -> NoteEditAction? {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased()
        switch modifiers {
        case [.command]:
            switch key {
            case "b": return .toggleInline(.bold)
            case "i": return .toggleInline(.italic)
            case "e": return .toggleInline(.code)
            case "k": return .toggleLink
            default: return nil
            }
        case [.command, .shift]:
            if key == "x" { return .toggleInline(.strikethrough) }
            if key == "b" { return .toggleQuote }
            switch event.keyCode {
            case DigitKey.seven: return .toggleList(.ordered)
            case DigitKey.eight: return .toggleList(.bullet)
            case DigitKey.nine: return .toggleList(.task)
            default: return nil
            }
        case [.command, .option]:
            if key == "c" { return .toggleCodeBlock }
            switch event.keyCode {
            case DigitKey.one: return .setHeading(level: 1)
            case DigitKey.two: return .setHeading(level: 2)
            case DigitKey.three: return .setHeading(level: 3)
            case DigitKey.zero: return .setHeading(level: 0)
            default: return nil
            }
        default:
            return nil
        }
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        guard rendersMarkdown else { return super.mouseDown(with: event) }
        guard !toggleTask(atContainerPoint: containerPoint(for: event)) else { return }
        isDragSelecting = true
        super.mouseDown(with: event)
        isDragSelecting = false
        editing?.dragSelectionEnded()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard rendersMarkdown, checkboxLine(atContainerPoint: containerPoint(for: event)) != nil else {
            return
        }
        NSCursor.arrow.set()
    }

    /// Toggles the task whose drawn box is under the point, leaving the caret where it was.
    func toggleTask(atContainerPoint point: CGPoint) -> Bool {
        guard let lineIndex = checkboxLine(atContainerPoint: point) else { return false }
        return perform(.toggleTask(lineIndex: lineIndex))
    }

    /// The source offset of the link edge a click landed on, when it is within a glyph's outer 30%.
    func linkEdge(ofLinkAt characterIndex: Int, clickedAt point: CGPoint) -> Int? {
        guard let storage = textStorage, characterIndex < storage.length else { return nil }
        var link = NSRange()
        let whole = NSRange(location: 0, length: storage.length)
        guard storage.attribute(.link, at: characterIndex, longestEffectiveRange: &link, in: whole) != nil,
            link.length > 0
        else { return nil }
        let edgeFraction: CGFloat = 0.3
        if let first = glyphFrame(at: link.location), first.minY <= point.y, point.y <= first.maxY,
            point.x <= first.minX + first.width * edgeFraction {
            return link.location
        }
        if let last = glyphFrame(at: NSMaxRange(link) - 1), last.minY <= point.y, point.y <= last.maxY,
            point.x >= last.maxX - last.width * edgeFraction {
            return NSMaxRange(link)
        }
        return nil
    }

    func containerPoint(for event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
    }

    private func checkboxLine(atContainerPoint point: CGPoint) -> Int? {
        guard let editing, let content = textContentStorage,
            let fragment = textLayoutManager?.textLayoutFragment(for: point) as? NoteBlockLayoutFragment,
            case .task(let level, _) = fragment.decoration.shape
        else { return nil }
        let firstLine = fragment.textLineFragments.first?.typographicBounds ?? .zero
        let box = NoteCheckboxGeometry.rect(
            level: level, firstLineHeight: firstLine.height,
            bodyPointSize: fragment.decoration.bodyPointSize
        ).offsetBy(dx: 0, dy: fragment.layoutFragmentFrame.minY + firstLine.minY)
        guard box.insetBy(dx: -Self.checkboxSlop, dy: -Self.checkboxSlop).contains(point) else { return nil }
        let start = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
        return editing.markdown.lineIndex(at: start)
    }

    private func glyphFrame(at characterIndex: Int) -> CGRect? {
        guard let layout = textLayoutManager, let content = textContentStorage,
            let start = content.location(content.documentRange.location, offsetBy: characterIndex),
            let end = content.location(start, offsetBy: 1),
            let range = NSTextRange(location: start, end: end)
        else { return nil }
        var frame: CGRect?
        layout.enumerateTextSegments(in: range, type: .standard, options: []) { _, segment, _, _ in
            frame = segment
            return false
        }
        return frame
    }

    // MARK: - Focus and appearance

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        isFirstResponder = true
        editing?.focusChanged()
        return true
    }

    override func resignFirstResponder() -> Bool {
        guard super.resignFirstResponder() else { return false }
        isFirstResponder = false
        editing?.focusChanged()
        return true
    }

    /// The panel keeps its first responder while another app is active, so key state is focus too.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        keyObservers = []
        guard let window else { return }
        let center = NotificationCenter.default
        keyObservers = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification].map { name in
            let token = center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.editing?.focusChanged() }
            }
            return NotificationToken(token, center: center)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        editing?.appearanceChanged()
    }
}
