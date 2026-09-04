import SwiftUI

/// The rounded surface every form control shares, so a field, a picker and an area read alike.
/// Written here, never in `DesignSystem»: how an extension's form looks is the feature's own.
struct ExtensionFieldChrome: ViewModifier {
    var focused: Bool
    /// A control that opens a popover keeps its focused edge while the popover has the keyboard.
    var open = false
    /// Lit under the pointer, so a control that can be clicked says so before it is.
    var hovered = false
    var height: CGFloat? = ExtensionFormMetrics.controlHeight

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, ExtensionFormMetrics.textInset)
            .frame(width: ExtensionFormMetrics.controlWidth, alignment: .leading)
            .frame(height: height, alignment: .topLeading)
            // A control is taller than its text, so the row's label would align to the box's top
            // rather than to the words in it. This puts the baseline back on the first line.
            .alignmentGuide(.firstTextBaseline) { _ in
                ExtensionFormMetrics.firstLineBaseline
            }
            .background(
                RoundedRectangle(
                    cornerRadius: ExtensionFormMetrics.cornerRadius, style: .continuous
                )
                .fill(hovered && !focused ? ExtensionColors.fieldHoverFill : ExtensionColors.fieldFill)
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: ExtensionFormMetrics.cornerRadius, style: .continuous
                )
                .strokeBorder(stroke, lineWidth: 1)
            )
            // The form draws its own focused edge, so AppKit's blue ring would be a second one.
            .focusEffectDisabled()
    }

    private var stroke: Color {
        if focused || open { return ExtensionColors.fieldFocusStroke }
        return hovered ? ExtensionColors.fieldHoverStroke : ExtensionColors.fieldStroke
    }
}

extension View {
    /// One control surface, so every row of a form lines up and reads as the same kind of thing.
    func extensionFieldChrome(
        focused: Bool, open: Bool = false, hovered: Bool = false,
        height: CGFloat? = ExtensionFormMetrics.controlHeight
    ) -> some View {
        modifier(
            ExtensionFieldChrome(
                focused: focused, open: open, hovered: hovered, height: height))
    }
}

/// The chevron a control that opens a popover carries, pointing the way it will open.
struct ExtensionDisclosureChevron: View {
    let open: Bool
    var flipped = false

    var body: some View {
        // Closed it always points down; open, it points back at the list it dropped.
        Image(systemName: pointsUp ? "chevron.up" : "chevron.down")
            .font(Theme.Typography.disclosure)
            .foregroundStyle(Theme.Colors.textSecondary)
    }

    private var pointsUp: Bool { open && !flipped }
}

/// One row of a picker popover: an optional icon, a title, and a trailing detail.
struct ExtensionPickerRow: View {
    let title: String
    var detail: String?
    var icon: ExtensionImage.Resolved?
    /// A multi-select picker marks what is already chosen.
    var checked = false
    let selected: Bool
    let onActivate: () -> Void

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: Theme.Spacing.sm) {
                if let icon {
                    ExtensionIconView(resolved: icon, size: 14)
                }
                Text(title)
                    .font(Theme.Typography.rowTitle)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.sm)
                if let detail {
                    Text(detail)
                        .font(Theme.Typography.rowTrailing)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if checked {
                    Image(systemName: "checkmark")
                        .font(Theme.Typography.disclosure)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            // Stated, not padded: the height maths counts rows, so a row is one exact height.
            .frame(
                maxWidth: .infinity, minHeight: ExtensionFormMetrics.popoverRowHeight,
                maxHeight: ExtensionFormMetrics.popoverRowHeight, alignment: .leading
            )
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.menuRow, style: .continuous)
                    .fill(selected ? Theme.Colors.menuHover : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}
