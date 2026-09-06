import SwiftUI

/// The numbered display tabs: they scope the canvas and target a newly added entry.
struct WindowLayoutDisplayTabs: View {
    let draft: WindowLayoutDraft
    let displays: [WindowLayoutDisplay]

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(Array(displays.enumerated()), id: \.element.uuid) { index, display in
                tab(display, ordinal: index + 1)
            }
        }
        .accessibilityLabel("Display")
    }

    private func tab(_ display: WindowLayoutDisplay, ordinal: Int) -> some View {
        let isSelected = draft.selectedDisplayUUID == display.uuid
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
        return Button {
            draft.select(displayUUID: display.uuid)
        } label: {
            Text("\(ordinal)")
                .font(Theme.Typography.keyCap)
                .monospacedDigit()
                .foregroundStyle(isSelected ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                .frame(width: Theme.Size.layoutDisplayTab, height: Theme.Size.layoutDisplayTab)
                .background(shape.fill(Theme.Colors.controlSurface))
                .overlay(shape.stroke(isSelected ? Color.accentColor : Theme.Colors.border))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help(display.name)
        .accessibilityLabel("Display \(ordinal), \(display.name)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The 3×3 anchor control: nine cells, each drawing the corner of a screen its window would take.
struct WindowLayoutPositionGrid: View {
    let selection: WindowLayoutAnchor
    let onSelect: (WindowLayoutAnchor) -> Void

    /// Reading order, three by three, so the grid cannot disagree with the enum.
    private static let rows: [[WindowLayoutAnchor]] = [
        [.topLeft, .top, .topRight], [.left, .center, .right],
        [.bottomLeft, .bottom, .bottomRight]
    ]

    var body: some View {
        Grid(horizontalSpacing: Theme.Spacing.xs, verticalSpacing: Theme.Spacing.xs) {
            ForEach(Self.rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { cell($0) }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Position")
    }

    private func cell(_ anchor: WindowLayoutAnchor) -> some View {
        let isSelected = anchor == selection
        let outline = RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
        let glyph = Theme.Size.layoutPositionGlyph
        let seat = RoundedRectangle(cornerRadius: Theme.Radius.barControl, style: .continuous)
        return Button {
            onSelect(anchor)
        } label: {
            ZStack(alignment: anchor.alignment) {
                outline.stroke(lineWidth: Theme.Size.layoutPositionStroke)
                RoundedRectangle(cornerRadius: Theme.Radius.glyph, style: .continuous)
                    .frame(
                        width: glyph.width * anchor.coverage.width,
                        height: glyph.height * anchor.coverage.height
                    )
                    .padding(Theme.Spacing.xxs)
            }
            .frame(width: glyph.width, height: glyph.height)
            .foregroundStyle(isSelected ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
            // The glyph floats in a wider seat, so a click anywhere in the cell lands on it.
            .frame(maxWidth: .infinity, minHeight: Theme.Size.layoutPositionCell)
            .background(seat.fill(isSelected ? Theme.Colors.selection : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(anchor.title)
        .accessibilityLabel(anchor.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// SwiftUI's own alignment, so it stays out of `Model/` and the purity grep.
extension WindowLayoutAnchor {
    /// How much of the plate the block covers: a pinned axis takes half, a spanned one all of it.
    fileprivate var coverage: CGSize {
        switch self {
        case .topLeft, .topRight, .bottomLeft, .bottomRight, .center:
            return CGSize(width: 0.5, height: 0.5)
        case .top, .bottom: return CGSize(width: 1, height: 0.5)
        case .left, .right: return CGSize(width: 0.5, height: 1)
        }
    }

    fileprivate var alignment: Alignment {
        switch self {
        case .topLeft: return .topLeading
        case .top: return .top
        case .topRight: return .topTrailing
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        case .bottomLeft: return .bottomLeading
        case .bottom: return .bottom
        case .bottomRight: return .bottomTrailing
        }
    }
}
