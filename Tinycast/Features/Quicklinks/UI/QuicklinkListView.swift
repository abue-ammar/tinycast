import AppKit
import SwiftUI

/// The Search Quicklinks screen: the whole library, pinned entries first.
struct QuicklinkList: View {
    @Environment(\.metrics) private var metrics
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
                .padding(.horizontal, metrics.spacing.md)
                .padding(.top, metrics.spacing.xs)
                .padding(.bottom, metrics.spacing.md)
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

    @Environment(\.metrics) private var metrics
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
        HStack(spacing: metrics.spacing.lg) {
            Image(nsImage: IconCache.symbolIcon(named: quicklink.symbol))
                .resizable()
                .frame(width: metrics.size.rowIcon, height: metrics.size.rowIcon)
            VStack(alignment: .leading, spacing: metrics.spacing.xxs) {
                Text(quicklink.name)
                    .font(metrics.typography.rowTitle)
                    .lineLimit(1)
                Text(quicklink.link)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: metrics.spacing.lg)
            if !quicklink.showsInRootSearch {
                Image(systemName: "eye.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            if let keycaps = hotKeys.binding(for: .quicklink(id: quicklink.id))?.keycaps {
                HStack(spacing: metrics.spacing.xxs) {
                    ForEach(Array(keycaps.enumerated()), id: \.offset) { _, cap in
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
    }
}

/// The detail pane beside the list, the way Search Snippets previews the snippet it highlights.
struct QuicklinkPreview: View {
    @Environment(\.metrics) private var metrics
    let quicklink: Quicklink?

    var body: some View {
        if let quicklink {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                SymbolImage(name: quicklink.symbol, size: Self.glyphSize)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, metrics.spacing.xl)
                Spacer(minLength: 0)
                QuicklinkInfoSection(quicklink: quicklink)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 12)
        } else {
            Color.clear
        }
    }

    /// Large enough to read as artwork, not as an oversized row icon.
    private static let glyphSize: CGFloat = 64
}

/// The "Information" block; everything in it is already in memory, so nothing is gathered off-main.
private struct QuicklinkInfoSection: View {
    @Environment(\.metrics) private var metrics
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
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            Text("Information")
                .font(metrics.typography.sectionHeader)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                let rows = self.rows
                ForEach(rows) { row in
                    if row.id != rows.first?.id { Divider() }
                    HStack(spacing: metrics.spacing.sm) {
                        Text(row.label).foregroundStyle(.secondary)
                        Spacer(minLength: metrics.spacing.lg)
                        Text(row.value).lineLimit(1).truncationMode(.middle)
                    }
                    .font(metrics.typography.keyCap)
                    .padding(.vertical, metrics.spacing.xs)
                }
            }
        }
        .padding(.vertical, metrics.spacing.md)
    }
}
