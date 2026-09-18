import SwiftUI

/// `PopoverMenuRow`'s look, copied: `PopoverMenu` reads palette state that Notes does not have.
struct NoteHeadingMenuView: View {
    @Environment(NotesCoordinator.self) private var notes

    private struct Row {
        let level: Int
        let title: String
        let shortcut: String
    }

    private static let rows = [
        Row(level: 1, title: "Heading 1", shortcut: "⌥⌘1"),
        Row(level: 2, title: "Heading 2", shortcut: "⌥⌘2"),
        Row(level: 3, title: "Heading 3", shortcut: "⌥⌘3"),
        Row(level: 0, title: "Text", shortcut: "⌥⌘0")
    ]

    private var surface: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.menuPanel, style: .continuous)
    }

    var body: some View {
        VStack(spacing: Theme.Size.menuRowSpacing) {
            ForEach(Self.rows, id: \.level) { row in
                NoteHeadingMenuRow(
                    title: row.title, shortcut: row.shortcut,
                    isCurrent: notes.formatting.headingLevel == row.level
                ) {
                    notes.chooseHeading(row.level)
                }
            }
        }
        .padding(Theme.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .glassEffect(.regular, in: surface)
        .clipShape(surface)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Heading")
    }
}

private struct NoteHeadingMenuRow: View {
    let title: String
    let shortcut: String
    let isCurrent: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "checkmark")
                    .font(
                        .system(
                            size: Theme.Typography.menuSymbolSize, weight: Theme.Typography.menuSymbolWeight)
                    )
                    .foregroundStyle(Theme.Colors.menuSymbol)
                    .opacity(isCurrent ? 1 : 0)
                    .frame(width: Theme.Size.menuIcon, height: Theme.Size.menuIcon)
                Text(title)
                    .font(Theme.Typography.menuRow)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.sm)
                HStack(spacing: Theme.Spacing.xxs) {
                    ForEach(Array(shortcut.enumerated()), id: \.offset) { _, glyph in
                        KeyCapChip(text: String(glyph), style: .outline)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(
                maxWidth: .infinity, minHeight: Theme.Size.menuRowHeight,
                maxHeight: Theme.Size.menuRowHeight, alignment: .leading
            )
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.menuRow, style: .continuous)
                    .fill(hovered ? Theme.Colors.menuHover : Color.clear))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovered = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
