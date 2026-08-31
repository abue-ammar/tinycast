import SwiftUI

/// Row order comes from `ExtensionScreen`, so the palette's flat index matches the draw.
struct ExtensionListView: View {
    @Environment(\.isDarkAppearance) private var isDark
    let screen: ExtensionScreen
    let selection: Int
    let assetsPath: String?
    /// Changes only when the list should scroll, so mouse selection never yanks it.
    let scroll: ScrollIntent
    let onSelect: (Int) -> Void
    let onActivate: (Int) -> Void
    let onActions: (Int) -> Void

    var body: some View {
        Group {
            if screen.items.isEmpty {
                emptyState
            } else if screen.showsDetail {
                HStack(spacing: 0) {
                    rowList
                        .frame(width: Theme.Size.clipboardListWidth)
                    Rectangle().fill(Theme.Colors.separator).frame(width: 1)
                    detailPane
                }
            } else if case .grid(let columns) = screen.kind {
                gridBody(columns: columns)
            } else {
                rowList
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if screen.isLoading {
            EmptyResults(text: "Loading…")
        } else if let empty = screen.emptyView {
            VStack(spacing: Theme.Spacing.md) {
                ExtensionIconView(
                    resolved: ExtensionImage.resolve(
                        empty.props["icon"], assetsPath: assetsPath, isDark: isDark),
                    size: 42)
                Text(empty.string("title") ?? "Nothing here")
                    .font(Theme.Typography.rowTitle)
                if let description = empty.string("description") {
                    Text(description)
                        .font(Theme.Typography.rowTrailing)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyResults(text: "No results")
        }
    }

    private var rowList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(screen.rows) { row in
                        switch row {
                        case .header(let title, let subtitle, _):
                            SectionHeader(
                                title: [title, subtitle].compactMap { $0 }.filter { !$0.isEmpty }
                                    .joined(separator: "  ·  "),
                                isFirst: row.id == screen.rows.first?.id)
                        case .item(let item):
                            ExtensionItemRow(
                                node: item.node, selected: item.index == selection,
                                assetsPath: assetsPath, compact: screen.showsDetail
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelect(item.index)
                                onActivate(item.index)
                            }
                            .onRightClick { onActions(item.index) }
                            .selectionFrame(item.index == selection)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll, row: selectedRowID, atOrigin: selection == 0, proxy: proxy)
        }
    }

    /// Scroll id of the selected item, or nil when the selection is out of range.
    private var selectedRowID: String? {
        screen.items.indices.contains(selection) ? screen.items[selection].id : nil
    }

    private func gridBody(columns: Int) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm), count: columns),
                    spacing: Theme.Spacing.sm
                ) {
                    ForEach(screen.items) { item in
                        ExtensionGridCell(
                            node: item.node, selected: item.index == selection,
                            assetsPath: assetsPath
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelect(item.index)
                            onActivate(item.index)
                        }
                        .onRightClick { onActions(item.index) }
                        .selectionFrame(item.index == selection)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll, row: selectedRowID, atOrigin: selection < columns, proxy: proxy)
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if screen.items.indices.contains(selection),
            let detail = screen.items[selection].node.node("detail")
        {
            ExtensionDetailBody(
                markdown: detail.string("markdown"), metadata: detail.node("metadata"),
                isLoading: detail.bool("isLoading") ?? false, assetsPath: assetsPath)
        } else {
            Color.clear
        }
    }
}

/// One `List.Item`: icon, title, subtitle, then its accessories right-aligned.
private struct ExtensionItemRow: View {
    @Environment(\.isDarkAppearance) private var isDark
    let node: RenderNode
    let selected: Bool
    let assetsPath: String?
    let compact: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            ExtensionIconView(
                resolved: ExtensionImage.resolve(node.props["icon"], assetsPath: assetsPath, isDark: isDark))
            Text(node.string("title") ?? "")
                .font(Theme.Typography.rowTitle)
                .lineLimit(1)
                // A detail list is 290pt wide, and an accessory would otherwise win the squeeze.
                .layoutPriority(1)
            if !compact, let subtitle = node.string("subtitle"), !subtitle.isEmpty {
                Text(subtitle)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.sm)
            // Raycast draws the accessories it is given, and a quota row's signal is all in them.
            ExtensionAccessoriesView(
                accessories: node.array("accessories"), assetsPath: assetsPath)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(fill)
        )
        .armedHover($hovered)
    }
}

/// `List.Item.Accessory` values: text, a tag, a date, an icon, or a combination.
struct ExtensionAccessoriesView: View {
    @Environment(\.isDarkAppearance) private var isDark
    let accessories: [RenderValue]
    let assetsPath: String?

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(Array(accessories.enumerated()), id: \.offset) { _, accessory in
                if let fields = accessory.objectValue {
                    accessoryView(fields)
                }
            }
        }
    }

    @ViewBuilder
    private func accessoryView(_ fields: [String: RenderValue]) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            if let icon = fields["icon"] {
                ExtensionIconView(
                    resolved: ExtensionImage.resolve(icon, assetsPath: assetsPath, isDark: isDark), size: 13)
            }
            if let tag = fields["tag"] {
                tagView(tag)
            }
            if let text = ExtensionAccessoriesView.label(fields["text"]) {
                Text(text)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(
                        ExtensionImage.color(fields["text"]?.objectValue?["color"], isDark: isDark)
                            ?? Theme.Colors.textSecondary
                    )
                    .lineLimit(1)
            }
            if let date = ExtensionAccessoriesView.date(fields["date"]) {
                Text(date, format: .relative(presentation: .numeric))
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
        }
        .help(fields["tooltip"]?.stringValue ?? "")
    }

    /// A tag is `{value, color}` or a bare string/date.
    @ViewBuilder
    private func tagView(_ tag: RenderValue) -> some View {
        let fields = tag.objectValue
        let text =
            ExtensionAccessoriesView.label(fields?["value"] ?? tag)
            ?? ExtensionAccessoriesView.date(fields?["value"] ?? tag).map {
                $0.formatted(date: .abbreviated, time: .omitted)
            }
        if let text {
            let color = ExtensionImage.color(fields?["color"], isDark: isDark) ?? Theme.Colors.textSecondary
            Text(text)
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(color)
                .padding(.horizontal, Theme.Spacing.xs)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(color.opacity(0.16))
                )
                .lineLimit(1)
        }
    }

    /// `text` may be a string or `{value, color}`.
    static func label(_ value: RenderValue?) -> String? {
        guard let value else { return nil }
        if let text = value.stringValue { return text }
        return value.objectValue?["value"]?.stringValue
    }

    static func date(_ value: RenderValue?) -> Date? {
        guard let value else { return nil }
        if let date = value.dateValue { return date }
        return value.objectValue?["value"]?.dateValue
    }
}

/// One `Grid.Item`: a large content tile with its title underneath.
private struct ExtensionGridCell: View {
    @Environment(\.isDarkAppearance) private var isDark
    let node: RenderNode
    let selected: Bool
    let assetsPath: String?
    @State private var hovered = false

    /// `content` is an `ImageLike`, `{value, tooltip}` or `{color}` — all `resolve`'s job.
    private var resolved: ExtensionImage.Resolved? {
        ExtensionImage.resolve(node.props["content"], assetsPath: assetsPath, isDark: isDark)
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            ExtensionIconView(resolved: resolved, size: 56, animates: true)
                .frame(maxWidth: .infinity)
                .padding(Theme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                        .fill(
                            selected
                                ? Theme.Colors.selection
                                : (hovered ? Theme.Colors.rowHover : ExtensionColors.gridItemFill))
                )
            if let title = node.string("title") {
                Text(title)
                    .font(Theme.Typography.rowTrailing)
                    .lineLimit(1)
            }
            if let subtitle = node.string("subtitle") {
                Text(subtitle)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .armedHover($hovered)
    }
}
