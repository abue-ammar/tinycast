import SwiftUI

/// Lays out a release body as a document. `AttributedString`'s parser only does inline styling, so
/// headings and bullets are placed here instead of arriving as literal `##` and `*`.
struct ReleaseNotesView: View {
    let text: String

    private var blocks: [ReleaseNotes.Block] { ReleaseNotes.blocks(from: text) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                view(for: block)
                    .padding(.top, isHeading(block) && index > 0 ? Theme.Spacing.md : 0)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: ReleaseNotes.Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(text)
                .font(level <= 2 ? .headline : .subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text("•").foregroundStyle(Theme.Colors.textSecondary)
                Text(markdown(text))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .paragraph(let text):
            Text(markdown(text))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func isHeading(_ block: ReleaseNotes.Block) -> Bool {
        if case .heading = block { return true }
        return false
    }

    /// GitHub release bodies are Markdown; anything it can't parse still reads fine as plain text.
    private func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
