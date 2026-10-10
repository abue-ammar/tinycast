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
}
