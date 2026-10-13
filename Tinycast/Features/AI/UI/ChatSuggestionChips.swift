import SwiftUI

struct ChatSuggestionChips: View {
    @Environment(\.metrics) private var metrics
    let choices: [String]
    let onChoose: (String) -> Void

    var body: some View {
        ChatFlowLayout(spacing: metrics.spacing.sm, centersRows: true) {
            ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
                ChatSuggestionChip(choice: choice, onChoose: onChoose)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggested replies")
    }
}

private struct ChatSuggestionChip: View {
    @Environment(\.metrics) private var metrics
    let choice: String
    let onChoose: (String) -> Void

    var body: some View {
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
            .chatChip()
        }
        .buttonStyle(.plain)
        .help("Reply “\(choice)”")
        .accessibilityLabel("Reply: \(choice)")
    }
}

private struct ChatChipSurface: ViewModifier {
    @Environment(\.metrics) private var metrics
    let leadsWithBadge: Bool

    func body(content: Content) -> some View {
        content
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.leading, leadsWithBadge ? metrics.spacing.sm : metrics.spacing.xl)
            .padding(.trailing, metrics.spacing.xl)
            .padding(.vertical, metrics.spacing.sm)
            .background { Capsule().fill(Color.clear).frosted(in: Capsule()) }
            .contentShape(Capsule())
    }
}

extension View {
    func chatChip(leadsWithBadge: Bool = false) -> some View {
        modifier(ChatChipSurface(leadsWithBadge: leadsWithBadge))
    }
}

struct ChatFlowLayout: Layout {
    let spacing: CGFloat
    var centersRows = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, width: width)
        let widest = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        let claimed = centersRows && width.isFinite ? width : min(widest, width)
        return CGSize(width: claimed, height: height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = centersRows ? bounds.minX + (bounds.width - row.width) / 2 : bounds.minX
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
