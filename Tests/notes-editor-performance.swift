import AppKit
import Foundation
import SwiftUI

/// Times the rendered Notes editor on a large note: install, one typed character, and a caret move.
@main
@MainActor
struct NotesEditorPerformance {
    private static let runs = 30

    static func main() {
        _ = NSApplication.shared
        let source = largeNote(characters: 100_000)
        let input = NoteEditorInput(id: NoteID(rawValue: "Large.md"), source: source, epoch: 0)
        let editor = makeEditor(input: input)
        let text = source as NSString

        var epoch = 0
        let install = median {
            epoch += 1
            editor.coordinator.update(NoteEditorInput(id: input.id, source: source, epoch: epoch))
        }
        let middleLine = text.lineRange(for: NSRange(location: text.length / 2, length: 0)).location
        let typing = [("end", text.length), ("middle", middleLine + 2), ("start", 2)].map { name, location in
            (name, median(prepare: { editor.textView.setSelectedRange(NSRange(location: location, length: 0)) }) {
                editor.textView.insertText("x", replacementRange: editor.textView.selectedRange())
            } after: {
                editor.textView.deleteBackward(nil)
            })
        }
        var nearTop = true
        let caret = median {
            nearTop.toggle()
            editor.textView.setSelectedRange(NSRange(location: nearTop ? 40 : middleLine, length: 0))
        }

        let report: [String: Any] = [
            "characters": text.length,
            "lines": editor.coordinator.renderer.markdown.lines.count,
            "runs": runs,
            "installAndRestyleMs": install,
            "typingMs": Dictionary(uniqueKeysWithValues: typing),
            "caretMoveMs": caret
        ]
        let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}")
        _ = editor.window
    }

    /// Median milliseconds of `body` over `runs`, with untimed setup and teardown around each run.
    private static func median(
        prepare: () -> Void = {}, _ body: () -> Void, after: () -> Void = {}
    ) -> Double {
        var samples: [Double] = []
        for _ in 0..<runs {
            prepare()
            let start = ContinuousClock.now
            body()
            let elapsed = ContinuousClock.now - start
            after()
            samples.append(Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1e3)
        }
        return (samples.sorted()[runs / 2] * 100).rounded() / 100
    }

    private static func largeNote(characters: Int) -> String {
        let block = """
            # Weekly plan
            Some **bold**, _italic_, ~~struck~~, `inline code` and [a link](https://example.com) here.
            - first bullet with https://example.org/path.
                - nested bullet under it
            1. ordered one
            2. ordered two
            - [ ] open task to do
            - [x] finished task
            > a quoted line of text
            ---
            ```swift
            let answer = 42
            print(answer)
            ```
            A closing paragraph that runs a little longer so wrapping happens at a narrow width.


            """
        return String(String(repeating: block, count: characters / block.utf16.count + 1).prefix(characters))
    }

    private static func makeEditor(
        input: NoteEditorInput
    ) -> (coordinator: NoteEditorView.Coordinator, textView: NoteTextView, window: NSWindow) {
        let view = NoteEditorView(
            input: input, rendersMarkdown: true, onSourceChange: { _ in }, onCharacterCountChange: { _, _ in },
            onFormattingChange: { _, _ in }, onReady: { _ in })
        let coordinator = NoteEditorView.Coordinator(parent: view)
        let textView = NoteTextView(usingTextLayoutManager: true)
        NoteEditorView.configure(textView)
        textView.delegate = coordinator
        textView.editorUndoManager = coordinator.editorUndoManager
        textView.setFrameSize(NSSize(width: 480, height: 1))
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 600))
        scrollView.documentView = textView
        let window = KeyWindow(contentRect: scrollView.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = scrollView
        coordinator.textView = textView
        coordinator.install(input, resetUndo: false)
        window.makeFirstResponder(textView)
        return (coordinator, textView, window)
    }
}

/// The editor reveals only in a key window, which a harness cannot otherwise have.
private final class KeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}
