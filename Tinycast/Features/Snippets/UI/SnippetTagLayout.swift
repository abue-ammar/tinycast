import SwiftUI

struct SnippetTagLayout: Layout {
    let spacing: CGFloat
    let lineHeight: CGFloat
    var trailing = false
    var inputMinimumWidth: CGFloat?
    var inputInset: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(width: proposal.width ?? lineHeight, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(width: bounds.width, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.0.x, y: bounds.minY + position.0.y),
                proposal: ProposedViewSize(position.1))
        }
    }

    private func layout(width: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [(CGPoint, CGSize)])
    {
        var positions: [(CGPoint, CGSize)] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight = lineHeight
        var rowStart = 0
        func finishRow() {
            guard trailing, let last = positions.last else { return }
            let offset = max(0, width - last.0.x - last.1.width)
            for index in rowStart..<positions.count { positions[index].0.x += offset }
        }
        for (index, view) in subviews.enumerated() {
            let isInput = inputMinimumWidth != nil && index == subviews.count - 1
            if isInput, x > 0 { x -= inputInset }
            var size = isInput ? .zero : view.sizeThatFits(ProposedViewSize(width: width, height: lineHeight))
            let needed = isInput ? min(inputMinimumWidth ?? width, width) : size.width
            if x > 0, x + needed > width {
                finishRow()
                rowStart = positions.count
                x = 0
                y += rowHeight + spacing
                rowHeight = lineHeight
            }
            if isInput { size = view.sizeThatFits(ProposedViewSize(width: max(0, width - x), height: nil)) }
            rowHeight = max(rowHeight, size.height)
            positions.append((CGPoint(x: x, y: y + max(0, (lineHeight - size.height) / 2)), size))
            x += size.width + spacing
        }
        finishRow()
        return (CGSize(width: width, height: subviews.isEmpty ? 0 : y + rowHeight), positions)
    }
}
