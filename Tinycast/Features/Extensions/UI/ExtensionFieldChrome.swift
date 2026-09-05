import SwiftUI

/// The one control surface a form draws, kept here rather than in `DesignSystem`.
struct ExtensionFieldChrome: ViewModifier {
    var focused: Bool
    /// A control that opens a popover keeps its focused edge while the popover has the keyboard.
    var open = false
    /// Lit under the pointer, so a control that can be clicked says so before it is.
    var hovered = false
    /// A one-line control centres its text; a text area starts at the top and grows down.
    var multiline = false

    private var height: CGFloat {
        multiline ? ExtensionFormMetrics.textAreaHeight : ExtensionFormMetrics.controlHeight
    }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, ExtensionFormMetrics.textInset)
            // One inset either way, so a text area's first line sits where a field's does.
            .padding(.vertical, ExtensionFormMetrics.verticalInset)
            .frame(
                width: ExtensionFormMetrics.controlWidth, height: height,
                alignment: multiline ? .topLeading : .leading
            )
            .background(
                RoundedRectangle(
                    cornerRadius: ExtensionFormMetrics.cornerRadius, style: .continuous
                )
                .fill(fill)
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

    private var fill: Color {
        hovered && !focused ? ExtensionColors.fieldHoverFill : ExtensionColors.fieldFill
    }

    private var stroke: Color {
        if focused || open { return ExtensionColors.fieldFocusStroke }
        return hovered ? ExtensionColors.fieldHoverStroke : ExtensionColors.fieldStroke
    }
}

extension View {
    /// One control surface, so every row of a form lines up and reads as the same kind of thing.
    func extensionFieldChrome(
        focused: Bool, open: Bool = false, hovered: Bool = false, multiline: Bool = false
    ) -> some View {
        modifier(
            ExtensionFieldChrome(
                focused: focused, open: open, hovered: hovered, multiline: multiline))
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
                    ExtensionIconView(resolved: icon, size: Theme.Size.menuIcon)
                }
                Text(title)
                    .font(Theme.Typography.menuRow)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.sm)
                if let detail {
                    Text(detail)
                        .font(Theme.Typography.menuShortcut)
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
