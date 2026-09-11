import Foundation

/// The geometry every form control shares; pure, so a harness drives the placement rule.
struct ExtensionFormMetrics {
    /// `Theme` at the default Interface Size, for the pure placement rule and its harness.
    static let base = ExtensionFormMetrics(scale: 1)

    /// Owned here rather than in `DesignSystem`: an extension never moves a launcher surface.
    let scale: CGFloat

    /// One control's width and height, in the proportions an extension's form is authored against.
    var controlWidth: CGFloat { scaled(360) }
    var controlHeight: CGFloat { scaled(32) }
    /// A text area is a control that grew: same width and chrome, several lines tall.
    var textAreaHeight: CGFloat { scaled(78) }
    /// Inset of a control's own text from its rounded edge.
    var textInset: CGFloat { scaled(10) }
    /// One top inset everywhere, so a field and a text area start their text on one line.
    var verticalInset: CGFloat { scaled(7) }
    /// `NSTextView`'s line-fragment padding, taken off so its text aligns with a field's.
    var textViewGutter: CGFloat { scaled(5) }
    /// The box a checkbox draws, and the gap to the label beside it.
    var checkboxSize: CGFloat { scaled(14) }
    /// The gap between one labelled row and the next, tuned by eye rather than derived.
    var rowSpacing: CGFloat { scaled(18) }
    /// The gap a separator adds on each side, so a group reads apart from the one before it.
    var separatorSpacing: CGFloat { scaled(4) }
    /// Room above the first row and below the last, so neither touches the bars.
    var formVerticalPadding: CGFloat { scaled(16) }
    /// The gap between a control and the popover it opens, on whichever side it opens.
    var popoverGap: CGFloat { scaled(6) }
    /// The ⌘K panel's pitch, restated: a launcher change must never move a form.
    var popoverRowHeight: CGFloat { scaled(36) }
    var popoverRowSpacing: CGFloat { 1 }
    /// A section heading inside a picker's list; shorter than a row, since it is a label.
    var popoverSectionHeaderHeight: CGFloat { scaled(24) }
    /// Six rows and half of the seventh, so a long list reads as scrollable rather than clipped.
    var popoverVisibleRows: CGFloat { 6.5 }
    /// The search or expression row a popover opens with, where it has one.
    var popoverSearchHeight: CGFloat { scaled(30) }
    /// The drawn caret that stands in for a field editor the control never gets.
    var caretWidth: CGFloat { 1 }
    var caretHeight: CGFloat { scaled(15) }
    var caretBlink: TimeInterval { 0.5 }
    /// How far left of an empty field's prompt its caret stands, as the field editor's does.
    var caretPromptGap: CGFloat { scaled(2) }
    /// `Theme.Spacing.sm` on every side, matching the ⌘K panel's own inset.
    var popoverPadding: CGFloat { scaled(6) }

    /// Rounded: a half-row of an odd pitch lands the popover's edge on a half pixel.
    var popoverRowsMaxHeight: CGFloat {
        (popoverVisibleRows * (popoverRowHeight + popoverRowSpacing)).rounded()
    }

    /// Exact, because every row is one known height: no measuring pass, and no greedy scroll view.
    func popoverListHeight(rows: Int, headers: Int = 0) -> CGFloat {
        guard rows > 0 else { return 0 }
        let pitch = popoverRowHeight + popoverRowSpacing
        let headings = CGFloat(headers) * (popoverSectionHeaderHeight + popoverRowSpacing)
        let exact = CGFloat(rows) * pitch - popoverRowSpacing + headings
        return min(exact, popoverRowsMaxHeight)
    }

    /// The whole popover, list plus whatever chrome sits above it.
    func popoverHeight(rows: Int, hasSearchField: Bool, headers: Int = 0) -> CGFloat {
        // The panel is sized to this, so an empty list must still measure the row it draws.
        let list = rows > 0 ? popoverListHeight(rows: rows, headers: headers) : popoverRowHeight
        let search = hasSearchField ? popoverSearchHeight : 0
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
    func placement(
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

    /// Whole points, matching `InterfaceMetrics`: a fractional pitch lands a row edge off-pixel.
    private func scaled(_ value: CGFloat) -> CGFloat {
        scale == 1 ? value : (value * scale).rounded()
    }
}
