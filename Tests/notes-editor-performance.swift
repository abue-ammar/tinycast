import AppKit
import Foundation

@main
@MainActor
struct NotesEditorPerformance {
    static func main() {
        _ = NSApplication.shared
        let unit = "Paragraph **bold** and [link](https://example.com) with `code`.\n"
        var source = String(repeating: unit, count: 4_000)
        source += String(repeating: "x", count: max(0, 250_000 - source.utf16.count))
        let parseStart = ContinuousClock.now
        let presentation = NoteMarkdownParser.parse(source)
        let parseTime = milliseconds(ContinuousClock.now - parseStart)
        let projectionStart = ContinuousClock.now
        _ = NoteDisplayProjection.build(
            source: source,
            presentation: presentation,
            activeSourceLocation: nil)
        let projectionTime = milliseconds(ContinuousClock.now - projectionStart)
        print(String(format: "Initial parse %.2f ms, projection %.2f ms", parseTime, projectionTime))
        let input = NoteEditorInput(id: NoteID(rawValue: "Performance.md"), source: source, epoch: 1)
        let view = NoteEditorView(
            input: input,
            onSourceChange: { _ in },
            onContentHeightChange: { _ in },
            onReady: { _ in },
            onOpenLink: { _ in })
        let coordinator = NoteEditorView.Coordinator(parent: view)
        let textView = NoteTextView(usingTextLayoutManager: true)
        textView.editorActions = coordinator
        textView.editorUndoManager = coordinator.editorUndoManager
        coordinator.textView = textView
        coordinator.install(input, resetUndo: false)

        for index in 0..<110 {
            let location = (textView.string as NSString).length / 2
            let start = ContinuousClock.now
            _ = coordinator.textView(
                textView,
                shouldChangeTextIn: NSRange(location: location, length: index.isMultiple(of: 2) ? 0 : 1),
                replacementString: index.isMultiple(of: 2) ? "x" : "")
            if index >= 10 { samples.append(milliseconds(ContinuousClock.now - start)) }
        }
        samples.sort()
        let median = samples[samples.count / 2]
        let p95 = samples[min(samples.count - 1, Int(Double(samples.count) * 0.95))]
        print(String(format: "NoteEditor.project 250k: median %.2f ms, p95 %.2f ms", median, p95))
    }

    private static var samples: [Double] = []

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
