import AppKit
import SwiftUI
import Testing

@testable import Tinycast

@MainActor
struct FormInputTests {
    // MARK: Single-line input

    @Test func singleLineInputIsANativeField() throws {
        let field = try SingleLineField()
        #expect(field.input.clipsToBounds)
        #expect(field.input.usesSingleLineMode)
        #expect(field.input.placeholderAttributedString?.string == "Placeholder")
        #expect(field.input.accessibilityLabel() == "Test")
        let insets = field.input.alignmentRectInsets
        #expect([insets.top, insets.bottom, insets.left, insets.right] == [0, 0, 0, 0])
    }

    @Test func singleLineTextKeepsItsHorizontalPadding() throws {
        let field = try SingleLineField()
        #expect(field.contentRect.minX == InterfaceMetrics.standard.spacing.xl)
    }

    @Test func focusingNeverMovesThePlaceholder() throws {
        let field = try SingleLineField()
        let resting = field.inkBounds()
        #expect(!resting.isNull)
        let editor = try field.focus()
        #expect(field.inkBounds() == resting)
        #expect(field.draft.focused)
        #expect(editor.frame == field.contentRect)
    }

    @Test func editingNeverMovesOrResizesTheField() throws {
        let field = try SingleLineField()
        let frame = field.input.frame
        let rect = field.contentRect
        let editor = try field.focus()
        for _ in 0..<3 {
            editor.insertText("Test", replacementRange: NSRange(location: 0, length: 0))
            editor.setSelectedRange(NSRange(location: 0, length: 4))
            editor.deleteBackward(nil)
            field.render()
            #expect(field.draft.name.isEmpty)
            #expect(field.input.frame == frame)
            #expect(editor.frame == rect)
            #expect(field.contentRect == rect)
        }
    }

    @Test func tabMovesThroughTheFormsFocusOrder() throws {
        let field = try SingleLineField()
        let editor = try field.focus()
        let delegate = try #require(field.input.delegate)
        let tab = #selector(NSResponder.insertTab(_:))
        #expect(delegate.control?(field.input, textView: editor, doCommandBy: tab) == true)
        #expect(field.movedBackwards == false)
        _ = delegate.control?(
            field.input, textView: editor, doCommandBy: #selector(NSResponder.insertBacktab(_:)))
        #expect(field.movedBackwards == true)
    }

    @Test func leavingTheFieldClearsFocusAndKeepsThePlaceholder() throws {
        let field = try SingleLineField()
        let resting = field.inkBounds()
        _ = try field.focus()
        field.window.makeFirstResponder(nil)
        field.render()
        #expect(field.inkBounds() == resting)
        #expect(!field.draft.focused)
    }

    @Test func textAndPlaceholderShareABaseline() throws {
        let field = try SingleLineField()
        let placeholder = field.inkBounds()
        field.draft.name = "Placeholder"
        field.render()
        #expect(abs(field.inkBounds().minY - placeholder.minY) <= 1)
    }

    // MARK: Cap-height alignment

    @Test(arguments: [1, 1.1, 1.2] as [CGFloat])
    func capitalsAreVerticallyCentered(scale: CGFloat) throws {
        let field = try SingleLineField(text: "H", metrics: InterfaceMetrics(scale: scale))
        let pixelsPerPoint = try field.pixelsPerPoint()
        #expect(abs(field.inkBounds().midY / pixelsPerPoint - field.height / 2) <= 0.5)
    }

    @Test(arguments: [1, 1.1, 1.2] as [CGFloat])
    func editingKeepsTheCapHeightAlignment(scale: CGFloat) throws {
        let field = try SingleLineField(text: "H", metrics: InterfaceMetrics(scale: scale))
        let resting = field.inkBounds()
        let editor = try field.focus()
        editor.setSelectedRange(NSRange(location: 1, length: 0))
        #expect(field.inkBounds() == resting)
    }

    @Test(arguments: [1, 1.1, 1.2] as [CGFloat])
    func nativeInputsAlignWithSwiftUIPickerText(scale: CGFloat) throws {
        let metrics = InterfaceMetrics(scale: scale)
        let field = try SingleLineField(text: "H", metrics: metrics)
        let text = Mounted(
            Text("H").font(metrics.typography.rowTitle).foregroundStyle(.white)
                .frame(width: 300, height: field.height),
            height: field.height)
        #expect(abs(text.inkBounds().midY - field.inkBounds().midY) <= 1)
    }

    // MARK: Text area

    @Test func textAreaIsANativeTextKit2View() throws {
        let area = try TextArea()
        #expect(area.input.clipsToBounds)
        #expect(area.input.isVerticallyResizable)
        #expect(area.input.textContainerInset.height == InterfaceMetrics.standard.spacing.md)
        #expect(area.input.textLayoutManager != nil)
        #expect(area.input.enclosingScrollView == nil)
        #expect(area.input.accessibilityLabel() == "Template")
    }

    @Test func loadingADraftCreatesNoUndoStep() throws {
        let area = try TextArea()
        #expect(area.input.undoManager?.canUndo == false)
    }

    @Test func longContentGrowsTheSameNativeView() throws {
        let area = try TextArea()
        area.draft.text = TextArea.longText
        area.render()
        #expect(area.find() === area.input)
        #expect(area.hosting.fittingSize.height > TextArea.minimumHeight)
    }

    @Test func programmaticInsertionIsUndoableWithCommandZ() throws {
        let area = try TextArea()
        area.type("Undo check")
        area.draft.text = TextArea.longText
        area.render()
        #expect(area.input.undoManager?.canUndo == true)
        #expect(area.input.performKeyEquivalent(with: try area.command("z")))
    }

    @Test func commandShiftZRedoesIntoTheBinding() throws {
        let area = try TextArea()
        area.type("Undo check")
        let typed = area.input.string
        area.draft.text = TextArea.longText
        area.render()
        _ = area.input.performKeyEquivalent(with: try area.command("z"))
        area.render()
        #expect(area.input.performKeyEquivalent(with: try area.command("Z", shift: true)))
        area.render()
        #expect(area.draft.text == area.input.string)
        #expect(area.draft.text != typed)
    }

    @Test func programmaticSelectionRestoresTheUnicodeCaret() throws {
        let area = try TextArea()
        let value = "Avant 👋{date} après"
        let caret = value.index(value.startIndex, offsetBy: 13)
        area.draft.text = value
        area.draft.selection = TextSelection(range: caret..<caret)
        area.render()
        #expect(area.input.selectedRange() == NSRange(caret..<caret, in: value))
    }

    @Test func shorterContentShrinksTheTextAreaToItsMinimum() throws {
        let area = try TextArea()
        area.draft.text = TextArea.longText
        area.render()
        area.draft.text = "Avant 👋{date} après"
        area.render()
        #expect(area.hosting.fittingSize.height <= TextArea.minimumHeight)
    }

    @Test func nativeRedoStaysSynchronizedWithTheBinding() throws {
        let area = try TextArea()
        area.type("Undo check")
        area.draft.text = "Avant 👋{date} après"
        area.render()
        area.input.undoManager?.undo()
        area.render()
        area.input.undoManager?.redo()
        area.render()
        #expect(area.draft.text == area.input.string)
    }

    /// A scroll view lays out once, so a text view that shrank would stay at the bottom.
    @Test func shortTextInAScrollViewKeepsTheMinimumHeight() throws {
        let draft = Draft()
        draft.text = "One line"
        let mounted = Mounted(
            ScrollView { TextAreaFixture(draft: draft) }.frame(height: TextArea.minimumHeight),
            height: TextArea.minimumHeight)
        let input = try #require(mounted.find(FormTextArea.InputView.self))
        mounted.window.makeFirstResponder(input)
        input.sizeToFit()
        #expect(input.frame.height >= TextArea.minimumHeight)
    }

    @Test func codeTextAreaUsesTheMonospacedBodyFont() throws {
        let area = try TextArea(isCode: true)
        let size = InterfaceMetrics.standard.typography.textNSFont(.body).pointSize
        #expect(area.input.font == NSFont.monospacedSystemFont(ofSize: size, weight: .regular))
    }

    @Test func codeTextAreaNeverRewritesShellSyntax() throws {
        let area = try TextArea(isCode: true)
        #expect(!area.input.isAutomaticQuoteSubstitutionEnabled)
        #expect(!area.input.isAutomaticDashSubstitutionEnabled)
        #expect(!area.input.isAutomaticTextReplacementEnabled)
        #expect(!area.input.isAutomaticSpellingCorrectionEnabled)
    }
}

// MARK: - Fixtures

/// A SwiftUI view in a borderless window of its own, closed when the test lets go of it.
@MainActor
private final class Mounted {
    let hosting: NSView
    let window: NSWindow

    init(_ view: some View, height: CGFloat) {
        hosting = NSHostingView(rootView: view)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: height),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        render()
    }

    isolated deinit {
        window.close()
    }

    /// Lays the host out, which is where SwiftUI applies a changed binding to its AppKit view.
    func render() {
        hosting.layoutSubtreeIfNeeded()
    }

    func find<T: NSView>(_ type: T.Type, in view: NSView? = nil) -> T? {
        let view = view ?? hosting
        if let match = view as? T { return match }
        return view.subviews.lazy.compactMap { self.find(type, in: $0) }.first
    }

    /// The bounds of the light pixels drawn, in pixels: where the text actually renders.
    func inkBounds() -> CGRect {
        guard let image = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return .null }
        hosting.cacheDisplay(in: hosting.bounds, to: image)
        var result = CGRect.null
        for y in 0..<image.pixelsHigh {
            for x in 0..<image.pixelsWide {
                if let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                    color.alphaComponent > 0.2, color.redComponent > 0.2
                {
                    result = result.union(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        return result
    }
}

@MainActor
private final class SingleLineField {
    let draft = Draft()
    let height: CGFloat
    let input: FormTextInput.InputView
    private let cell: FormTextInput.InputCell
    private let mounted: Mounted
    private let moves = Moves()

    var window: NSWindow { mounted.window }
    var movedBackwards: Bool? { moves.backwards }
    var contentRect: CGRect { cell.contentRect(forBounds: input.bounds) }

    init(text: String = "", metrics: InterfaceMetrics = .standard) throws {
        draft.name = text
        height = metrics.size.dialogButtonHeight
        let moves = moves
        mounted = Mounted(
            SingleLineFixture(draft: draft, moveFocus: { moves.backwards = $0 })
                .environment(\.metrics, metrics).frame(width: 300, height: height),
            height: height)
        input = try #require(mounted.find(FormTextInput.InputView.self))
        cell = try #require(input.cell as? FormTextInput.InputCell)
    }

    func render() { mounted.render() }
    func inkBounds() -> CGRect { mounted.inkBounds() }

    func pixelsPerPoint() throws -> CGFloat {
        let image = try #require(mounted.hosting.bitmapImageRepForCachingDisplay(in: mounted.hosting.bounds))
        return CGFloat(image.pixelsHigh) / height
    }

    /// Takes first responder and returns the field editor AppKit supplies for it.
    func focus() throws -> NSTextView {
        window.makeFirstResponder(input)
        render()
        return try #require(input.currentEditor() as? NSTextView)
    }

    private final class Moves {
        var backwards: Bool?
    }
}

@MainActor
private final class TextArea {
    static let minimumHeight: CGFloat = 120
    static let longText = String(repeating: "A long line to wrap in the editor.\n", count: 40)

    let draft = Draft()
    let input: FormTextArea.InputView
    private let mounted: Mounted

    var window: NSWindow { mounted.window }
    var hosting: NSView { mounted.hosting }

    init(isCode: Bool = false) throws {
        mounted = Mounted(TextAreaFixture(draft: draft, isCode: isCode), height: Self.minimumHeight)
        input = try #require(mounted.find(FormTextArea.InputView.self))
    }

    func render() { mounted.render() }
    func find() -> FormTextArea.InputView? { mounted.find(FormTextArea.InputView.self) }

    /// Types `text` into the focused area, as a keystroke would.
    func type(_ text: String) {
        window.makeFirstResponder(input)
        input.insertText(text, replacementRange: NSRange(location: 0, length: 0))
    }

    func command(_ key: String, shift: Bool = false) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: shift ? [.command, .shift] : .command,
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: key,
                charactersIgnoringModifiers: key, isARepeat: false, keyCode: 6))
    }
}

@Observable
private final class Draft {
    var text = ""
    var selection: TextSelection?
    var name = ""
    var focused = false
}

private struct SingleLineFixture: View {
    @Bindable var draft: Draft
    var moveFocus: (Bool) -> Void

    var body: some View {
        FormTextInput(
            text: $draft.name, focused: $draft.focused,
            placeholder: "Placeholder", label: "Test", moveFocus: moveFocus)
    }
}

private struct TextAreaFixture: View {
    @Bindable var draft: Draft
    var isCode = false

    var body: some View {
        FormTextArea(
            text: $draft.text, selection: $draft.selection, focused: .constant(false),
            minimumHeight: TextArea.minimumHeight, label: "Template", isCode: isCode, moveFocus: { _ in }
        ).frame(width: 300)
    }
}
