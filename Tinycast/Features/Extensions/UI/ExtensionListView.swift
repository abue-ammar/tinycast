import SwiftUI

/// The List / Grid screen of a running extension command. Row order comes from `ExtensionScreen` so the
/// flat selection index the palette owns always matches what's drawn.
struct ExtensionListView: View {
    let screen: ExtensionScreen
    let selection: Int
    let assetsPath: String?
    /// Changes only when the list should scroll, so mouse selection never yanks it.
    let scroll: ScrollIntent
    let onSelect: (Int) -> Void
    let onActivate: () -> Void
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
                    resolved: ExtensionImage.resolve(empty.props["icon"], assetsPath: assetsPath),
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
                        case .item(let node):
                            let index = screen.items.firstIndex(of: node) ?? 0
                            ExtensionItemRow(
                                node: node, selected: index == selection, assetsPath: assetsPath,
                                compact: screen.showsDetail
                            )
                            .id(String(node.id))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelect(index)
                                onActivate()
                            }
                            .onRightClick { onActions(index) }
                            .selectionFrame(index == selection)
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
        screen.items.indices.contains(selection) ? String(screen.items[selection].id) : nil
    }

    private func gridBody(columns: Int) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm), count: columns),
                    spacing: Theme.Spacing.sm
                ) {
                    ForEach(Array(screen.items.enumerated()), id: \.element.id) { index, node in
                        ExtensionGridCell(
                            node: node, selected: index == selection, assetsPath: assetsPath
                        )
                        .id(String(node.id))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelect(index)
                            onActivate()
                        }
                        .onRightClick { onActions(index) }
                        .selectionFrame(index == selection)
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
            let detail = screen.items[selection].node("detail")
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
                resolved: ExtensionImage.resolve(node.props["icon"], assetsPath: assetsPath))
            Text(node.string("title") ?? "")
                .font(Theme.Typography.rowTitle)
                .lineLimit(1)
            if !compact, let subtitle = node.string("subtitle"), !subtitle.isEmpty {
                Text(subtitle)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.sm)
            if !compact {
                ExtensionAccessoriesView(
                    accessories: node.array("accessories"), assetsPath: assetsPath)
            }
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
                    resolved: ExtensionImage.resolve(icon, assetsPath: assetsPath), size: 13)
            }
            if let tag = fields["tag"] {
                tagView(tag)
            }
            if let text = ExtensionAccessoriesView.label(fields["text"]) {
                Text(text)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(
                        ExtensionImage.color(fields["text"]?.objectValue?["color"])
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
            let color = ExtensionImage.color(fields?["color"]) ?? Theme.Colors.textSecondary
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
    let node: RenderNode
    let selected: Bool
    let assetsPath: String?
    @State private var hovered = false

    /// `content` is an `ImageLike`, or `{value, tooltip}` wrapping one, or `{color}` — all three are
    /// `ExtensionImage.resolve`'s job.
    private var resolved: ExtensionImage.Resolved? {
        ExtensionImage.resolve(node.props["content"], assetsPath: assetsPath)
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
                                : (hovered ? Theme.Colors.rowHover : Color.white.opacity(0.03)))
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
