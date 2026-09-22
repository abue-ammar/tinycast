import SwiftUI

/// A reply's choices as the next thing to say: glass capsules that send themselves.
struct ChatSuggestionChips: View {
    @Environment(\.metrics) private var metrics
    let choices: [String]
    let onChoose: (String) -> Void

    var body: some View {
        ChatFlowLayout(spacing: metrics.spacing.sm) {
            ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
                Button {
                    onChoose(choice)
                } label: {
                    HStack(spacing: metrics.spacing.sm) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(metrics.typography.keyCap)
                            .foregroundStyle(Theme.Colors.textTertiary)
                        Text(choice)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .font(metrics.typography.rowTrailing)
                    .padding(.horizontal, metrics.spacing.xs)
                    .padding(.vertical, metrics.spacing.xxs)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .help("Reply “\(choice)”")
                .accessibilityLabel("Reply: \(choice)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggested replies")
    }
}

/// Chips left to right, wrapping when the row is full.
struct ChatFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, width: width)
        let widest = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: min(widest, width), height: height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = fitted(subviews[index], width: bounds.width)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// A chip wider than the row is squeezed to it, where its label truncates.
    private func fitted(_ subview: LayoutSubview, width: CGFloat) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        guard ideal.width > width, width.isFinite else { return ideal }
        return subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = fitted(subviews[index], width: width)
            if !row.indices.isEmpty, row.width + spacing + size.width > width {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
