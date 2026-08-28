import SwiftUI

struct SnippetsList: View {
    let results: [StoredSnippet]
    let selectedID: StoredSnippet.ID?
    let scroll: ScrollIntent
    let onSelect: (StoredSnippet) -> Void
    let onActivate: () -> Void
    let onActions: (StoredSnippet) -> Void

    private var firstRowSelected: Bool {
        selectedID != nil && selectedID == results.first?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results) { record in
                        SnippetRow(record: record, selected: record.id == selectedID)
                            .selectionFrame(record.id == selectedID)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(record) }
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded {
                                    onSelect(record)
                                    onActivate()
                                }
                            )
                            .onRightClick { onActions(record) }
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
                scroll, row: selectedID, atOrigin: firstRowSelected, proxy: proxy)
        }
    }
}

private struct SnippetRow: View {
    let record: StoredSnippet
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous)
                .fill(Theme.Colors.controlSurface)
                .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
                .overlay(
                    Image(systemName: "curlybraces")
                        .font(.system(size: 12))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary))
            Text(record.snippet.name)
                .font(Theme.Typography.rowTitle)
                .lineLimit(1)
            Spacer(minLength: Theme.Spacing.lg)
            if let keyword = record.snippet.keyword, !keyword.isEmpty {
                Text(keyword)
                    .font(Theme.Typography.keyCap)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
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

struct SnippetPreview: View {
    let record: StoredSnippet?

    var body: some View {
        if let record {
            VStack(alignment: .leading, spacing: 0) {
                // The raw template: expanding here would read the clipboard on every arrow key.
                ScrollView {
                    Text(record.snippet.text)
                        .font(.system(.subheadline, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                SnippetInfoSection(record: record)
            }
            .padding(.horizontal, 12)
        } else {
            Color.clear
        }
    }
}

/// The "Information" block; everything in it is already in memory, so nothing is gathered off-main.
private struct SnippetInfoSection: View {
    let record: StoredSnippet

    private struct InfoRow: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    private var rows: [InfoRow] {
        var rows = [InfoRow(label: "Name", value: record.snippet.name)]
        if let keyword = record.snippet.keyword, !keyword.isEmpty {
            rows.append(InfoRow(label: "Keyword", value: keyword))
        }
        rows.append(InfoRow(label: "File", value: record.fileURL.lastPathComponent))
        rows.append(
            InfoRow(label: "Characters", value: record.snippet.text.count.formatted()))
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Information")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                let rows = self.rows
                ForEach(rows) { row in
                    if row.id != rows.first?.id { Divider() }
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(row.label).foregroundStyle(.secondary)
                        Spacer(minLength: Theme.Spacing.lg)
                        Text(row.value).lineLimit(1).truncationMode(.middle)
                    }
                    .font(Theme.Typography.keyCap)
                    .padding(.vertical, Theme.Spacing.xs)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.md)
    }
}
