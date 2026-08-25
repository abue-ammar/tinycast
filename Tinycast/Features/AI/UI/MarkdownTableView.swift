import SwiftUI

struct MarkdownTableView: View {
    let table: MarkdownBlock.Table

    var body: some View {
        Grid(
            alignment: .leadingFirstTextBaseline, horizontalSpacing: Theme.Spacing.xl,
            verticalSpacing: Theme.Spacing.sm
        ) {
            GridRow {
                ForEach(Array(table.header.enumerated()), id: \.offset) { column, cell in
                    Text(MarkdownInline.attributed(cell))
                        .font(Theme.Typography.sectionHeader)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .gridColumnAlignment(alignment(at: column))
                }
            }
            GridRow {
                Rectangle()
                    .fill(Theme.Colors.cardStroke)
                    .frame(height: Theme.Size.hairline)
                    .gridCellUnsizedAxes(.horizontal)
                    .gridCellColumns(table.header.count)
            }
            ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(MarkdownInline.attributed(cell))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        // Given only a width, Grid measures a wrapping row a line short of what it draws, and the
        // transcript's scroll view then stops above the message's own end.
        .fixedSize(horizontal: false, vertical: true)
        .padding(Theme.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(Theme.Colors.cardStroke))
    }

    private func alignment(at column: Int) -> HorizontalAlignment {
        switch table.alignments[column] {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}
