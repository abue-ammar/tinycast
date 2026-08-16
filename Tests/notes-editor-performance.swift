import AppKit
import Foundation

@main
@MainActor
struct NotesEditorPerformance {
    static func main() {
        _ = NSApplication.shared
        let unit = "A plain Markdown paragraph with enough text to wrap across the editor.\n"
        let targetLength = 250_000
        var source = String(repeating: unit, count: targetLength / unit.utf16.count)
        source += String(repeating: "x", count: targetLength - source.utf16.count)
        let input = NoteEditorInput(
            id: NoteID(rawValue: "Performance.md"),
            source: source,
            epoch: 1)
        let view = NoteEditorView(
            input: input,
            onSourceChange: { _ in },
            onContentHeightChange: { _, _ in },
            onReady: { _ in })
        let coordinator = NoteEditorView.Coordinator(parent: view)
        let textView = NoteTextView(usingTextLayoutManager: true)
        NoteEditorView.configure(textView)
        textView.delegate = coordinator
        textView.editorUndoManager = coordinator.editorUndoManager
        textView.setFrameSize(NSSize(width: Theme.Size.noteWidth, height: 1))
        coordinator.textView = textView
        coordinator.install(input, resetUndo: false)
        coordinator.reportHeight()

        var samples: [Double] = []
        for index in 0..<110 {
            let location = (textView.string as NSString).length / 2
            let range =
                index.isMultiple(of: 2)
                ? NSRange(location: location, length: 0)
                : NSRange(location: location - 1, length: 1)
            let replacement = index.isMultiple(of: 2) ? "x" : ""
            let start = ContinuousClock.now
            textView.insertText(replacement, replacementRange: range)
            if index >= 10 {
                samples.append(milliseconds(ContinuousClock.now - start))
            }
        }

        samples.sort()
        let median = samples[samples.count / 2]
        let p95 = samples[min(samples.count - 1, Int(Double(samples.count) * 0.95))]
        print(String(format: "Plain Notes edit 250k: median %.2f ms, p95 %.2f ms", median, p95))
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
