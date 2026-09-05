import Foundation

/// The geometry every form control shares; pure, so a harness drives the placement rule.
enum ExtensionFormMetrics {
    /// One control's width and height, matching the proportions Raycast's own form draws.
    static let controlWidth: CGFloat = 360
    static let controlHeight: CGFloat = 32
    /// A text area is a control that grew: same width and chrome, several lines tall.
    static let textAreaHeight: CGFloat = 78
    /// Inset of a control's own text from its rounded edge.
    static let textInset: CGFloat = 10
    /// One top inset everywhere, so a field and a text area start their text on one line.
    static let verticalInset: CGFloat = 7
    /// `NSTextView`'s line-fragment padding, taken off so its text aligns with a field's.
    static let textViewGutter: CGFloat = 5
    /// The box a checkbox draws, and the gap to the label beside it.
    static let checkboxSize: CGFloat = 14
    /// The gap between one labelled row and the next, measured off Raycast's own form.
    static let rowSpacing: CGFloat = 18
    /// The gap a separator adds on each side, so a group reads apart from the one before it.
    static let separatorSpacing: CGFloat = 4
    /// Room above the first row and below the last, so neither touches the bars.
    static let formVerticalPadding: CGFloat = 16
    /// The gap between a control and the popover it opens, on whichever side it opens.
    static let popoverGap: CGFloat = 6
    /// The ⌘K panel's pitch, restated: a launcher change must never move a form.
    static let popoverRowHeight: CGFloat = 36
    static let popoverRowSpacing: CGFloat = 1
    /// A section heading inside a picker's list; shorter than a row, since it is a label.
    static let popoverSectionHeaderHeight: CGFloat = 24
    /// Six rows and half of the seventh, so a long list reads as scrollable rather than clipped.
    static let popoverVisibleRows: CGFloat = 6.5
    /// The search or expression row a popover opens with, where it has one.
    static let popoverSearchHeight: CGFloat = 30
    /// The drawn caret that stands in for a field editor the control never gets.
    static let caretWidth: CGFloat = 1
    static let caretHeight: CGFloat = 15
    static let caretBlink: TimeInterval = 0.5
    /// `Theme.Spacing.sm` on every side, matching the ⌘K panel's own inset.
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
