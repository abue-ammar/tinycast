import SwiftUI

/// The numbered display tabs: they scope the canvas and target a newly added entry.
struct WindowLayoutDisplayTabs: View {
    let draft: WindowLayoutDraft
    let displays: [WindowLayoutDisplay]
    @Environment(\.self) private var environment

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
                .frame(width: Theme.Size.layoutDisplayTab, height: Theme.Size.layoutDisplayTab)
                .background(shape.fill(Theme.Colors.controlSurface))
                .overlay(shape.stroke(isSelected ? Color.accentColor : Theme.Colors.border))
        }
        .buttonStyle(.plain)
        .help(display.name)
        .accessibilityLabel("Display \(ordinal), \(display.name)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The 3×3 anchor control: nine labelled buttons, each drawing where its window would sit.
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
        .accessibilityLabel("Position")
    }

    private func cell(_ anchor: WindowLayoutAnchor) -> some View {
        let isSelected = anchor == selection
        let outer = RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
        let side = Theme.Size.layoutPositionCell
        // A `ZStack` alignment, not an overlay's: the glyph must sit in the corner it names.
        return Button {
            onSelect(anchor)
        } label: {
            ZStack(alignment: anchor.alignment) {
                outer.stroke(isSelected ? Color.accentColor : Theme.Colors.border)
                RoundedRectangle(cornerRadius: Theme.Radius.glyph, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Theme.Colors.textTertiary)
                    .frame(
                        width: side * Theme.Size.layoutPositionGlyph,
                        height: side * Theme.Size.layoutPositionGlyph
                    )
                    .padding(Theme.Spacing.xxs)
            }
            .frame(width: side, height: side)
        }
        .buttonStyle(.plain)
        .help(anchor.title)
        .accessibilityLabel(anchor.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// SwiftUI's own alignment, so it stays out of `Model/` and the purity grep.
extension WindowLayoutAnchor {
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
