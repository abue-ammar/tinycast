import SwiftUI

/// Inline markdown for one block. `Text` renders emphasis on its own but not code or strikethrough.
enum MarkdownInline {
    static func attributed(_ source: String, _ metrics: InterfaceMetrics) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.failurePolicy = .returnPartiallyParsedIfPossible
        guard var text = try? AttributedString(markdown: source, options: options) else {
            return AttributedString(source)
        }
        let intents = text.runs.compactMap { run in run.inlinePresentationIntent.map { ($0, run.range) } }
        for (intent, range) in intents {
            if intent.contains(.code) {
                text[range].font = metrics.typography.inlineCode
                text[range].backgroundColor = Theme.Colors.controlSurface
            }
            if intent.contains(.strikethrough) { text[range].strikethroughStyle = .single }
        }
        return text
    }

    static func headingFont(_ level: Int, _ metrics: InterfaceMetrics) -> Font {
        switch level {
        case 1: metrics.typography.markdownHeading1
        case 2: metrics.typography.markdownHeading2
        default: metrics.typography.markdownHeading3
        }
    }
}
