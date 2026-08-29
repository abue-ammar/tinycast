import SwiftUI

/// Renders parsed markdown; the body is erased so a nested list cannot make `Body` circular.
struct MarkdownView: View {
    let blocks: [MarkdownBlock]
    var spacing = Theme.Spacing.lg

    var body: AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: spacing) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { offset, block in
                    MarkdownBlockView(block: block)
                        .padding(.top, offset > 0 && block.isHeading ? Theme.Spacing.sm : 0)
                }
            })
    }
}

extension MarkdownBlock {
    /// A heading opens a section, so it takes more air above it than two paragraphs need.
    fileprivate var isHeading: Bool {
        if case .heading = self { return true }
        return false
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(MarkdownInline.attributed(text))
                .font(MarkdownInline.headingFont(level))
                .fixedSize(horizontal: false, vertical: true)
        case .paragraph(let text):
            Text(MarkdownInline.attributed(text))
                .fixedSize(horizontal: false, vertical: true)
        case .bulletList(let items):
            MarkdownListView(items: items, start: nil)
        case .numberedList(let start, let items):
            MarkdownListView(items: items, start: start)
        case .code(let language, let text):
            MarkdownCodeView(language: language, text: text)
        case .quote(let blocks):
            MarkdownQuoteView(blocks: blocks)
        case .table(let table):
            MarkdownTableView(table: table)
        case .rule:
            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(height: Theme.Size.hairline)
        }
    }
}

private struct MarkdownListView: View {
    let items: [MarkdownBlock.Item]
    /// Nil for a bulleted list; otherwise the number the first item counts from.
    let start: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    marker(at: offset, checked: item.checked)
                        .frame(minWidth: Theme.Size.markdownListMarker, alignment: .trailing)
                    MarkdownView(blocks: item.blocks, spacing: Theme.Spacing.xs)
                }
            }
        }
    }

    @ViewBuilder private func marker(at offset: Int, checked: Bool?) -> some View {
        if let checked {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .foregroundStyle(checked ? Theme.Colors.success : Theme.Colors.textTertiary)
        } else if start != nil {
            // Padding to the list's widest number keeps a marker from wrapping mid-number.
            Text(orderedMarker(at: offset))
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: true, vertical: false)
        } else {
            Text("•").foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    /// Right-aligned within the list by padding, since monospaced digits all measure the same.
    private func orderedMarker(at offset: Int) -> String {
        guard let start else { return "" }
        let widest = String(start + max(items.count - 1, 0)).count
        let number = String(start + offset)
        return String(repeating: " ", count: max(0, widest - number.count)) + number + "."
    }
}

private struct MarkdownQuoteView: View {
    let blocks: [MarkdownBlock]

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.lg) {
            RoundedRectangle(cornerRadius: Theme.Radius.keyCap, style: .continuous)
                .fill(Theme.Colors.border)
                .frame(width: Theme.Size.markdownQuoteBar)
            MarkdownView(blocks: blocks)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
