import CoreGraphics

/// The geometry every form control shares, so a field, a picker and a text area line up exactly.
/// Pure numbers, so the popover's placement rule can be driven by a harness.
enum ExtensionFormMetrics {
    /// One control's width and height, matching the proportions Raycast's own form draws.
    static let controlWidth: CGFloat = 360
    static let controlHeight: CGFloat = 32
    /// A text area is a control that grew: same width and chrome, several lines tall.
    static let textAreaHeight: CGFloat = 78
    static let cornerRadius: CGFloat = 10
    /// Inset of a control's own text from its rounded edge.
    static let textInset: CGFloat = 10
    /// The box a checkbox draws, and the gap to the label beside it.
    static let checkboxSize: CGFloat = 14
    /// The gap between one labelled row and the next.
    static let rowSpacing: CGFloat = 14
    /// Where a control's first line of text sits from its top edge, which is what a row's label
    /// aligns to: a tall control would otherwise drag the label to the top of the box.
    static let firstLineBaseline: CGFloat = 21
    /// The gap between a control and the popover it opens, on whichever side it opens.
    static let popoverGap: CGFloat = 6
    static let popoverRowHeight: CGFloat = 32
    static let popoverRowSpacing: CGFloat = 1
    /// A section heading inside a picker's list; shorter than a row, since it is a label.
    static let popoverSectionHeaderHeight: CGFloat = 24
    /// Six rows and half of the seventh, so a long list reads as scrollable rather than clipped.
    static let popoverVisibleRows: CGFloat = 6.5
    static let popoverCornerRadius: CGFloat = 10
    /// The search or expression row a popover opens with, where it has one.
    static let popoverSearchHeight: CGFloat = 34
    static let popoverPadding: CGFloat = 6

    /// Rounded: a half-row of an odd pitch lands the popover's edge on a half pixel.
    static var popoverRowsMaxHeight: CGFloat {
        (popoverVisibleRows * (popoverRowHeight + popoverRowSpacing)).rounded()
    }

    /// Exact, because every row is one known height: no measuring pass, and no greedy scroll view.
    static func popoverListHeight(rows: Int, headers: Int = 0) -> CGFloat {
        guard rows > 0 else { return 0 }
        let pitch = popoverRowHeight + popoverRowSpacing
        let headings = CGFloat(headers) * (popoverSectionHeaderHeight + popoverRowSpacing)
        let exact = CGFloat(rows) * pitch - popoverRowSpacing + headings
        return min(exact, popoverRowsMaxHeight)
    }

    /// The whole popover, list plus whatever chrome sits above it.
    static func popoverHeight(rows: Int, hasSearchField: Bool, headers: Int = 0) -> CGFloat {
        let list = popoverListHeight(rows: rows, headers: headers)
        let search = hasSearchField ? popoverSearchHeight : 0
        // An empty list still draws its search row, so the popover never collapses to its padding.
        return list + search + popoverPadding * 2
    }

    /// Where a popover sits, given the control it belongs to and the room around it.
    struct Placement: Equatable {
        /// Top edge of the popover, in the same space the anchor was measured in.
        let y: CGFloat
        /// True when there was no room below and the popover opened upwards instead.
        let flipped: Bool
    }

    /// Below the control when it fits, else above it; clamped so it can never leave the container.
    static func placement(
        anchor: CGRect, popoverHeight: CGFloat, containerHeight: CGFloat
    ) -> Placement {
        let below = anchor.maxY + popoverGap
        let above = anchor.minY - popoverGap - popoverHeight
        // Preferred, exactly as a menu does: open downward unless the bottom would cut it off.
        if below + popoverHeight <= containerHeight {
            return Placement(y: below, flipped: false)
        }
        if above >= 0 {
            return Placement(y: above, flipped: true)
        }
        // Taller than the container either way: show its start, which is where the selection is.
        return Placement(y: max(0, min(below, containerHeight - popoverHeight)), flipped: false)
    }
}
