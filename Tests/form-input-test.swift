import AppKit
import SwiftUI

@main
@MainActor
struct FormInputTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        _ = NSApplication.shared
        testSingleLine()
        testTokenCommands()
        testTokenLayout()
        testCapAlignment()
        testTextArea()
        testCodeFont()
        if failures > 0 { exit(1) }
        print("Form inputs passed")
    }

    static func window(content: NSView, height: CGFloat) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: height),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = content
        content.layoutSubtreeIfNeeded()
        return window
    }

    static func testSingleLine() {
        let draft = Draft()
        var backwards: Bool?
        let height = InterfaceMetrics.standard.size.dialogButtonHeight
        let hosting = NSHostingView(
            rootView: SingleLineFixture(draft: draft, moveFocus: { backwards = $0 })
                .frame(width: 300, height: height))
        let window = window(content: hosting, height: height)
        defer { window.close() }
        guard let input = find(FormTextInput.InputView.self, in: hosting),
            let cell = input.cell as? FormTextInput.InputCell
        else {
            expect(false, "single-line input mounts an NSTextField")
            return
        }
        expect(input.clipsToBounds, "the native field clips to its own bounds")
        expect(input.usesSingleLineMode, "AppKit owns single-line text behavior")
        expect(input.placeholderAttributedString?.string == "Placeholder", "placeholder is native")
        expect(input.accessibilityLabel() == "Test", "native input has an accessibility label")
        let frame = input.frame
        let rect = cell.contentRect(forBounds: input.bounds)
        expect(rect.minX == InterfaceMetrics.standard.spacing.xl, "text keeps its horizontal padding")
        let alignment = input.alignmentRectInsets
        expect(
            [alignment.top, alignment.bottom, alignment.left, alignment.right].allSatisfy { $0 == 0 },
            "the native field does not outgrow its chrome")
        let restingInk = inkBounds(hosting)
        expect(!restingInk.isNull, "the placeholder rendering test captures visible text")
        window.makeFirstResponder(input)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        expect(inkBounds(hosting) == restingInk, "focusing never moves the rendered placeholder")
        expect(draft.focused, "taking first responder updates focus before typing")
        guard let editor = input.currentEditor() as? NSTextView else {
            expect(false, "AppKit supplies the single-line field editor")
            return
        }
        expect(editor.frame == rect, "resting text and field editor share the same rectangle")
        for _ in 0..<3 {
            editor.insertText("Test", replacementRange: NSRange(location: 0, length: 0))
            editor.setSelectedRange(NSRange(location: 0, length: 4))
            editor.deleteBackward(nil)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            input.layoutSubtreeIfNeeded()
            expect(draft.name.isEmpty, "native typing and deletion update the binding")
            expect(input.frame == frame, "editing never resizes the single-line field")
            expect(editor.frame == rect, "deletion never moves the field editor")
            expect(
                cell.contentRect(forBounds: input.bounds) == rect, "empty placeholder keeps its origin"
            )
        }
        let delegate = input.delegate!
        expect(
            delegate.control?(input, textView: editor, doCommandBy: #selector(NSResponder.insertTab(_:)))
                == true,
            "Tab goes through the form's focus order")
        expect(backwards == false, "Tab advances focus")
        _ = delegate.control?(input, textView: editor, doCommandBy: #selector(NSResponder.insertBacktab(_:)))
        expect(backwards == true, "Shift-Tab reverses focus")
        window.makeFirstResponder(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        expect(inkBounds(hosting) == restingInk, "leaving the field never moves the rendered placeholder")
        expect(!draft.focused, "leaving the field clears focus")
        draft.name = "Placeholder"
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        expect(
            abs(inkBounds(hosting).minY - restingInk.minY) <= 1,
            "text and placeholder share the same rendered baseline")
    }

    static func testTokenCommands() {
        let draft = Draft()
        var advanced = false
        var commands: [Selector] = []
        let newline = #selector(NSResponder.insertNewline(_:))
        let tab = #selector(NSResponder.insertTab(_:))
        let height = InterfaceMetrics.standard.size.dialogButtonHeight
        let hosting = NSHostingView(
            rootView: TokenFixture(
                draft: draft, moveFocus: { _ in advanced = true },
                onCommand: {
                    commands.append($0); return $0 == newline
                }
            ).frame(width: 300, height: height))
        let window = window(content: hosting, height: height)
        defer { window.close() }
        guard let input = find(FormTextArea.InputView.self, in: hosting), let delegate = input.delegate else {
            expect(false, "token input mounts a native text view and delegate")
            return
        }
        expect(
            input.textContainerInset.width == InterfaceMetrics.standard.spacing.xxs,
            "a token input owns its text inset")
        window.makeFirstResponder(input)
        expect(
            delegate.textView?(input, doCommandBy: newline) == true,
            "a token input consumes its own Return")
        expect(!advanced, "a handled command does not change focus")
        expect(
            delegate.textView?(input, doCommandBy: tab) == true,
            "unhandled token commands keep native form focus traversal")
        expect(advanced && commands == [newline, tab], "custom commands run before normal traversal")
    }

    static func testTokenLayout() {
        let draft = Draft()
        draft.name = "H"
        let metrics = InterfaceMetrics.standard
        let height = metrics.size.dialogButtonHeight - metrics.spacing.sm * 2
        let hosting = NSHostingView(rootView: TokenFixture(draft: draft).frame(width: 300))
        let window = window(content: hosting, height: height * 4)
        defer { window.close() }
        guard let input = find(FormTextArea.InputView.self, in: hosting) else {
            expect(false, "tag input mounts a native text view")
            return
        }
        guard let scroll = input.enclosingScrollView else {
            expect(false, "token input uses native horizontal scrolling")
            return
        }
        expect(!input.isVerticallyResizable, "pending tags never grow a second line")
        expect(
            !scroll.hasVerticalScroller && !scroll.hasHorizontalScroller,
            "token scrolling does not show scrollbars")
        expect(scroll.contentView.clipsToBounds, "pending text clips behind the fixed tags")
        expect(scroll.documentView === input, "only the pending name owns the scroll document")
        window.makeFirstResponder(input)
        for value in ["", "H", "a", ""] {
            input.insertText(
                value, replacementRange: NSRange(location: 0, length: (input.string as NSString).length))
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            hosting.layoutSubtreeIfNeeded()
            let caret = input.convert(
                window.convertFromScreen(
                    input.firstRect(forCharacterRange: input.selectedRange(), actualRange: nil)),
                from: nil)
            expect(
                abs(caret.midY - height / 2) <= 0.5,
                "empty and filled token inputs vertically center the caret")
        }
        input.insertText("H", replacementRange: NSRange(location: 0, length: 0))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        let baseline = inkBounds(input).minY
        for tags in [[], ["Work"], ["Work", "Personal"], ["Work", "Personal", "Other", "More"], []] {
            draft.tags = tags
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            hosting.layoutSubtreeIfNeeded()
            expect(window.firstResponder === input, "adding tokens preserves native focus")
            expect(
                inkBounds(input).minY == baseline, "moving input never moves its text baseline")
            expect(input.frame.height == height, "all token rows keep the compact height")
            let tagsInRow = tags.count > 3 ? tags.count - 3 : tags.count
            let leading = tags.isEmpty ? metrics.spacing.md : CGFloat(tagsInRow) * (80 + metrics.spacing.xs)
            expect(
                scroll.convert(scroll.bounds, to: hosting).minX - metrics.spacing.sm
                    + input.textContainerInset.width == leading
                    && input.textContainerInset.width == metrics.spacing.xxs,
                "typing uses the chip gap after tags and restores the larger inset when empty")
            expect(
                hosting.fittingSize.height
                    == metrics.size.dialogButtonHeight + (tags.count > 3 ? height + metrics.spacing.xs : 0),
                "validated tokens wrap with a compact row gap")
            if tags.isEmpty {
                expect(
                    input.frame.width >= scroll.contentSize.width,
                    "the native editor covers the empty field's click and cursor area")
            }
        }
        draft.tags = ["Work", "Personal", "Other"]
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        hosting.layoutSubtreeIfNeeded()
        let frame = scroll.convert(scroll.bounds, to: hosting)
        let longName = String(repeating: "Long tag name ", count: 15)
        input.insertText(longName, replacementRange: NSRange(location: 0, length: input.string.utf16.count))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        hosting.layoutSubtreeIfNeeded()
        let suffix = String(repeating: "0123456789", count: 10)
        for character in suffix {
            input.insertText(String(character), replacementRange: input.selectedRange())
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        hosting.layoutSubtreeIfNeeded()
        expect(
            draft.name == longName + suffix, "typing during horizontal scrolling never loses characters"
        )
        expect(
            scroll.convert(scroll.bounds, to: hosting) == frame,
            "typing a long pending tag never moves it below the validated tokens")
        expect(
            hosting.fittingSize.height == metrics.size.dialogButtonHeight,
            "pending tag text stays on one row at the regular field height")
        expect(input.frame.width > scroll.contentSize.width, "long pending tags extend the native document")
        expect(scroll.contentView.bounds.minX > 0, "native scrolling keeps the caret visible")
        let endOffset = scroll.contentView.bounds.minX
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        hosting.layoutSubtreeIfNeeded()
        expect(scroll.contentView.bounds.minX == 0, "manual scrolling can reveal the pending name's start")
        input.moveToEndOfLine(nil)
        input.moveToBeginningOfLine(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        expect(scroll.contentView.bounds.minX < endOffset, "native navigation scrolls back to the start")
        input.moveToEndOfLine(nil)
        expect(scroll.contentView.bounds.minX > 0, "native navigation keeps the end visible")
    }

    static func testCapAlignment() {
        for scale: CGFloat in [1, 1.1, 1.2] {
            let metrics = InterfaceMetrics(scale: scale)
            let draft = Draft()
            draft.name = "H"
            let height = metrics.size.dialogButtonHeight
            let hosting = NSHostingView(
                rootView: SingleLineFixture(draft: draft, moveFocus: { _ in })
                    .environment(\.metrics, metrics).frame(width: 300, height: height))
            let window = window(content: hosting, height: height)
            let image = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
            let pixelsPerPoint = CGFloat(image.pixelsHigh) / height
            let restingInk = inkBounds(hosting)
            let input = find(FormTextInput.InputView.self, in: hosting)!
            expect(
                abs(restingInk.midY / pixelsPerPoint - height / 2) <= 0.5,
                "capitals are vertically centered at scale \(scale)")
            window.makeFirstResponder(input)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            guard let editor = input.currentEditor() as? NSTextView else {
                expect(false, "cap-height test receives a native field editor")
                window.close()
                continue
            }
            editor.setSelectedRange(NSRange(location: 1, length: 0))
            expect(
                inkBounds(hosting) == restingInk,
                "editing preserves the cap-height alignment at scale \(scale)")
            let swiftUI = NSHostingView(
                rootView: Text("H").font(metrics.typography.rowTitle)
                    .foregroundStyle(.white).frame(width: 300, height: height))
            let other = Self.window(content: swiftUI, height: height)
            expect(
                abs(inkBounds(swiftUI).midY - restingInk.midY) <= 1,
                "native inputs align with SwiftUI picker text at scale \(scale)")
            other.close()
            window.close()
        }
    }

    static func inkBounds(_ view: NSView) -> CGRect {
        let image = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: image)
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

    static func testTextArea() {
        let height: CGFloat = 120
        let draft = Draft()
        let hosting = NSHostingView(rootView: TextAreaFixture(draft: draft))
        let window = window(content: hosting, height: height)
        defer { window.close() }
        guard let input = find(FormTextArea.InputView.self, in: hosting) else {
            expect(false, "textarea mounts an NSTextView")
            return
        }
        expect(input.clipsToBounds, "textarea tracking stays inside its bounds")
        expect(input.isVerticallyResizable, "textarea grows instead of internally scrolling")
        expect(
            input.textContainerInset.height == InterfaceMetrics.standard.spacing.md,
            "textarea keeps its top padding")
        expect(input.textLayoutManager != nil, "textarea uses TextKit 2")
        expect(input.enclosingScrollView == nil, "textarea has no internal scroll view")
        expect(input.accessibilityLabel() == "Template", "textarea has an accessibility label")
        expect(input.undoManager?.canUndo == false, "loading a draft creates no undo step")
        window.makeFirstResponder(input)
        input.insertText("Undo check", replacementRange: NSRange(location: 0, length: 0))
        for character in "0123456789" {
            input.insertText(String(character), replacementRange: input.selectedRange())
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        expect(
            draft.text == "Undo check0123456789", "textarea edits never lose characters to a stale binding")
        if let selection = draft.selection, case .selection(let range) = selection.indices {
            expect(
                NSRange(range, in: draft.text) == input.selectedRange(),
                "rapid edits preserve the selection binding")
        } else {
            expect(false, "rapid edits update the selection binding")
        }
        let previous = input.string
        draft.text = String(repeating: "A long line to wrap in the editor.\n", count: 40)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        hosting.layoutSubtreeIfNeeded()
        expect(
            find(FormTextArea.InputView.self, in: hosting) === input,
            "binding updates preserve native view identity")
        expect(hosting.fittingSize.height > height, "long content expands the textarea")
        expect(input.undoManager?.canUndo == true, "programmatic insertion uses native undo")
        let undo = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "z",
            charactersIgnoringModifiers: "z", isARepeat: false, keyCode: 6)!
        expect(input.performKeyEquivalent(with: undo), "the focused textarea handles Command-Z")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        expect(input.string == previous, "undo restores the content before programmatic insertion")
        expect(draft.text == previous, "native undo reaches the binding")
        let redo = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "Z",
            charactersIgnoringModifiers: "Z", isARepeat: false, keyCode: 6)!
        expect(input.performKeyEquivalent(with: redo), "the focused textarea handles Command-Shift-Z")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        expect(draft.text == input.string && draft.text != previous, "native redo reaches the binding")
        input.undoManager?.undo()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        window.makeFirstResponder(nil)
        draft.text += "{date}"
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        input.undoManager?.undo()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        expect(draft.text == previous, "placeholder insertion remains undoable after a menu takes focus")
        let value = "Avant 👋{date} après"
        let caret = value.index(value.startIndex, offsetBy: 13)
        draft.text = value
        draft.selection = TextSelection(range: caret..<caret)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        hosting.layoutSubtreeIfNeeded()
        expect(
            input.selectedRange() == NSRange(caret..<caret, in: value),
            "programmatic insertion restores the Unicode caret, not the end of the textarea")
        expect(hosting.fittingSize.height <= height, "deletion shrinks the textarea to its minimum")
        input.undoManager?.redo()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        expect(draft.text == input.string, "native redo stays synchronized with the binding")
    }

    static func testCodeFont() {
        let draft = Draft()
        let hosting = NSHostingView(rootView: TextAreaFixture(draft: draft, isCode: true))
        let window = window(content: hosting, height: 120)
        defer { window.close() }
        let font = find(FormTextArea.InputView.self, in: hosting)?.font
        expect(
            font
                == NSFont.monospacedSystemFont(
                    ofSize: InterfaceMetrics.standard.typography.textNSFont(.body).pointSize, weight: .regular
                ),
            "code textareas use the native monospaced font at the shared body size")
        let input = find(FormTextArea.InputView.self, in: hosting)
        expect(
            input?.isAutomaticQuoteSubstitutionEnabled == false
                && input?.isAutomaticDashSubstitutionEnabled == false
                && input?.isAutomaticTextReplacementEnabled == false
                && input?.isAutomaticSpellingCorrectionEnabled == false,
            "code textareas do not rewrite shell syntax while typing")
    }

    static func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let input = view as? T { return input }
        for child in view.subviews {
            if let input = find(type, in: child) { return input }
        }
        return nil
    }

    @Observable
    final class Draft {
        var text = ""
        var selection: TextSelection?
        var name = ""
        var focused = false
        var tags: [String] = []
    }

    struct SingleLineFixture: View {
        @Bindable var draft: Draft
        var moveFocus: (Bool) -> Void

        var body: some View {
            FormTextInput(
                text: $draft.name, focused: $draft.focused,
                placeholder: "Placeholder", label: "Test", moveFocus: moveFocus)
        }
    }

    struct TextAreaFixture: View {
        @Bindable var draft: Draft
        var isCode = false

        var body: some View {
            FormTextArea(
                text: $draft.text, selection: $draft.selection, focused: .constant(false),
                minimumHeight: 120, label: "Template", isCode: isCode, moveFocus: { _ in }
            ).frame(width: 300)
        }
    }

    struct TokenFixture: View {
        @Bindable var draft: Draft
        var moveFocus: (Bool) -> Void = { _ in }
        var onCommand: ((Selector) -> Bool)?

        var body: some View {
            let metrics = InterfaceMetrics.standard
            let height = metrics.size.dialogButtonHeight - metrics.spacing.sm * 2
            let font = metrics.typography.textNSFont(.body)
            let inset = (height - ceil(font.ascender - font.descender + font.leading)) / 2
            return SnippetTagLayout(
                spacing: metrics.spacing.xs, lineHeight: height,
                inputMinimumWidth: metrics.spacing.xl * 2, inputInset: metrics.spacing.xxs
            ) {
                ForEach(draft.tags, id: \.self) { Text($0).frame(width: 80, height: height) }
                FormTextArea(
                    text: $draft.name, selection: .constant(nil), focused: $draft.focused,
                    minimumHeight: height, label: "Tags", allowsLineBreaks: false,
                    moveFocus: moveFocus, insets: NSSize(width: metrics.spacing.xxs, height: inset),
                    onCommand: onCommand, scrollsHorizontally: true
                )
                .padding(.leading, draft.tags.isEmpty ? metrics.spacing.md - metrics.spacing.xxs : 0)
                .padding(.trailing, metrics.spacing.md - metrics.spacing.xxs)
            }
            .padding(metrics.spacing.sm)
        }
    }
}
