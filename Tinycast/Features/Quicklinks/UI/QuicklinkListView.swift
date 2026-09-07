import AppKit
import SwiftUI

/// The Search Quicklinks screen: the whole library, pinned entries first.
struct QuicklinkList: View {
    let results: [Quicklink]
    let selectedID: Quicklink.ID?
    /// Changes only when the list should scroll, so mouse selection never yanks the position.
    let scroll: ScrollIntent
    let onSelect: (Quicklink) -> Void
    let onActivate: () -> Void
    let onActions: (Quicklink) -> Void

    private enum Row: Identifiable {
        case header(String)
        case item(Quicklink)
        var id: String {
            switch self {
            case .header(let title): return "header-" + title
            case .item(let quicklink): return quicklink.id.uuidString
            }
        }
    }

    /// Whether the selection sits on flat index 0, whose section header should stay visible.
    private var firstRowSelected: Bool {
        selectedID != nil && selectedID == results.first?.id
    }

    /// The store publishes pinned-first, so this emits a header on the one boundary.
    private var rows: [Row] {
        var rows: [Row] = []
        var currentTitle: String?
        for quicklink in results {
            let title = quicklink.isPinned ? "Pinned" : "Quicklinks"
            if title != currentTitle {
                rows.append(.header(title))
                currentTitle = title
            }
            rows.append(.item(quicklink))
        }
        return rows
    }

    var body: some View {
        let rows = rows
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        switch row {
                        case .header(let title):
                            SectionHeader(title: title, isFirst: row.id == rows.first?.id)
                        case .item(let quicklink):
                            QuicklinkRow(
                                quicklink: quicklink, selected: quicklink.id == selectedID
                            )
                            .selectionFrame(quicklink.id == selectedID)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(quicklink) }
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded {
                                    onSelect(quicklink)
                                    onActivate()
                                }
                            )
                            .onRightClick { onActions(quicklink) }
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
                scroll, row: selectedID?.uuidString, atOrigin: firstRowSelected, proxy: proxy)
        }
    }
}

private struct QuicklinkRow: View {
    let quicklink: Quicklink
    let selected: Bool
    @Environment(HotKeyManager.self) private var hotKeys
    @State private var hovered = false

    /// Selection wins over hover when a row is both; otherwise hover shows its fainter layer.
    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(nsImage: IconCache.symbolIcon(named: quicklink.symbol))
                .resizable()
                .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(quicklink.name)
                    .font(Theme.Typography.rowTitle)
                    .lineLimit(1)
                Text(quicklink.link)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: Theme.Spacing.lg)
            if !quicklink.showsInRootSearch {
                Image(systemName: "eye.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            if let keycaps = hotKeys.binding(for: .quicklink(id: quicklink.id))?.keycaps {
                HStack(spacing: Theme.Spacing.xxs) {
                    ForEach(Array(keycaps.enumerated()), id: \.offset) { _, cap in
                        KeyCapChip(text: cap, style: .outline)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
    }
}

/// The detail pane beside the list, the way Search Snippets previews the snippet it highlights.
struct QuicklinkPreview: View {
    let quicklink: Quicklink?

    var body: some View {
        if let quicklink {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                SymbolImage(name: quicklink.symbol, size: Self.glyphSize)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.xl)
                Spacer(minLength: 0)
                QuicklinkInfoSection(quicklink: quicklink)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 12)
        } else {
            Color.clear
        }
    }

    /// Large enough to read as the artwork Raycast shows there, not as an oversized row icon.
    private static let glyphSize: CGFloat = 64
}

/// The "Information" block; everything in it is already in memory, so nothing is gathered off-main.
private struct QuicklinkInfoSection: View {
    let quicklink: Quicklink
    @Environment(HotKeyManager.self) private var hotKeys
    @Environment(AppIndex.self) private var appIndex

    private struct InfoRow: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    /// Relative day plus exact time; shared, `DateFormatter` being expensive to build.
    @MainActor private static let createdFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    private var rows: [InfoRow] {
        var rows = [
            InfoRow(label: "Name", value: quicklink.name),
            InfoRow(label: "Link", value: quicklink.link)
        ]
        if let bundleID = quicklink.openWithBundleID {
            rows.append(
                InfoRow(
                    label: "Open With",
                    value: AppPresentation.resolve(bundleID: bundleID, in: appIndex).name))
        }
        if let keycaps = hotKeys.binding(for: .quicklink(id: quicklink.id))?.keycaps {
            rows.append(InfoRow(label: "Shortcut", value: keycaps.joined()))
        }
        rows.append(
            InfoRow(label: "Created", value: Self.createdFormatter.string(from: quicklink.createdAt)))
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
