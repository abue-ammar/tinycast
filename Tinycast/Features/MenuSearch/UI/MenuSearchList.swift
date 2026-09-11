import SwiftUI

struct MenuSearchList: View {

    @Environment(\.metrics) private var metrics
    let items: [MenuSearchItem]
    let targetName: String
    let iconURL: URL?
    let iconStamp: Int
    let selectedID: MenuSearchItem.ID?
    let scroll: ScrollIntent
    let onActivate: (MenuSearchItem) -> Void

    /// One bitmap for the whole list; every row paints the same frozen app icon.
    @State private var icon: NSImage?

    private var firstRowSelected: Bool {
        selectedID != nil && selectedID == items.first?.id
    }

    private var iconKey: String { "\(iconURL?.path ?? "")|\(iconStamp)" }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    SectionHeader(title: targetName, isFirst: true)
                    ForEach(items) { item in
                        MenuSearchRow(item: item, icon: icon, selected: item.id == selectedID)
                            .selectionFrame(item.id == selectedID)
                            .contentShape(Rectangle())
                            .onTapGesture { onActivate(item) }
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.top, metrics.spacing.xs)
                .padding(.bottom, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll, row: selectedID, atOrigin: firstRowSelected, proxy: proxy)
        }
        // Keyed on the icon, so a restyle re-decodes instead of freezing the outgoing bitmap.
        .task(id: IconRequest(iconKey)) {
            guard let iconURL else { return }
            if let warm = IconCache.cached(.file(stamp: iconStamp), fileURL: iconURL) {
                icon = warm
                return
            }
            icon = await IconCache.loadAsync(.file(stamp: iconStamp), fileURL: iconURL)
        }
    }
}

private struct MenuSearchRow: View {

    @Environment(\.metrics) private var metrics
    let item: MenuSearchItem
    let icon: NSImage?
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable()
                } else {
                    RoundedRectangle(cornerRadius: metrics.radius.thumbnail, style: .continuous)
                        .fill(Theme.Colors.iconPlaceholder)
                }
            }
            .frame(width: metrics.size.rowIcon, height: metrics.size.rowIcon)
            Text(item.title)
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
            Spacer(minLength: metrics.spacing.md)
            Text(item.displayPath)
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            let caps = item.shortcut?.keycaps ?? []
            if !caps.isEmpty {
                HStack(spacing: metrics.spacing.xxs) {
                    ForEach(caps, id: \.self) { cap in
                        KeyCapChip(text: cap, style: .outline)
                    }
                }
            }
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.title)
        .accessibilityValue(item.displayPath)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
