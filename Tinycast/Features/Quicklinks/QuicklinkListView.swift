import AppKit
import SwiftUI

/// The Search Quicklinks screen: the whole library, pinned entries first.
struct QuicklinkList: View {
    let results: [Quicklink]
    let selectedID: Quicklink.ID?
    /// Changes only when the list should scroll (keyboard nav / reset), so mouse selection never yanks the scroll position.
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

    /// The store already publishes pinned-first order, so this walks and emits a header on the one
    /// boundary — mirrors the clipboard's Pinned section.
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
            .pinOriginOnInsetSettle(scroll, proxy: proxy)
            .onChange(of: scroll) { _, scroll in
                switch scroll.kind {
                case .top:
                    proxy.scrollToOrigin()
                case .follow:
                    if firstRowSelected {
                        proxy.scrollToOrigin()
                    } else if let selectedID {
                        proxy.reveal(selectedID.uuidString)
                    }
                }
            }
        }
    }
}

private struct QuicklinkRow: View {
    let quicklink: Quicklink
    let selected: Bool
    @EnvironmentObject private var hotKeys: HotKeyManager
    @State private var hovered = false

    /// Selection wins over hover when a row is both; otherwise hover shows its fainter layer.
    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(nsImage: IconCache.symbolIcon(named: symbol))
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

    private var symbol: String {
        quicklink.iconSymbol ?? QuicklinkDestination.detect(quicklink.link)?.defaultSymbol
            ?? Quicklink.sfSymbol
    }
}

/// The ⌘K menu for a quicklink row.
@MainActor
enum QuicklinkActionsMenu {
    static func content(quicklink: Quicklink, core: AppCore) -> PopoverMenuContent {
        var items: [PopoverMenuItem] = [
            PopoverMenuItem(title: "Open Quicklink", systemImage: symbol(quicklink), shortcut: "↵") {
                core.openQuicklink(id: quicklink.id)
            }
        ]
        // `PopoverMenu` is a flat list with no picker, so choosing an *arbitrary* app belongs to the
        // editor, which has one. What the palette can usefully offer is the one alternative that
        // always exists: bypass the saved app and use the system handler, once.
        if quicklink.openWithBundleID != nil {
            items.append(
                PopoverMenuItem(
                    title: "Open With Default App", systemImage: "arrow.up.forward.app",
                    shortcut: "⌘↵"
                ) {
                    core.openQuicklink(id: quicklink.id, forcingDefaultApp: true)
                })
        }
        items.append(
            PopoverMenuItem(title: "Edit Quicklink", systemImage: "pencil") {
                core.hidePalette(restoreFocus: false)
                core.editQuicklink(quicklink)
            })
        items.append(
            PopoverMenuItem(title: "Duplicate Quicklink", systemImage: "plus.square.on.square") {
                core.duplicateQuicklink(id: quicklink.id)
            })
        items.append(
            quicklink.isPinned
                ? PopoverMenuItem(title: "Unpin Quicklink", systemImage: "pin.slash", shortcut: "⌘P")
                { core.toggleQuicklinkPinned(id: quicklink.id) }
                : PopoverMenuItem(title: "Pin Quicklink", systemImage: "pin", shortcut: "⌘P") {
                    core.toggleQuicklinkPinned(id: quicklink.id)
                })
        items.append(
            PopoverMenuItem(
                title: quicklink.showsInRootSearch
                    ? "Hide from Root Search" : "Show in Root Search",
                systemImage: quicklink.showsInRootSearch ? "eye.slash" : "eye"
            ) {
                core.setQuicklinkShowsInRootSearch(!quicklink.showsInRootSearch, id: quicklink.id)
            })
        // Revealing only makes sense once the destination is a real path — a template's isn't known
        // until it expands, and a URL has no file to show.
        if case .path(let path)? = QuicklinkDestination.detect(quicklink.link),
            !QuicklinkDestination.containsPlaceholder(quicklink.link) {
            items.append(
                PopoverMenuItem(title: "Show in Finder", systemImage: "folder", shortcut: "⌘F") {
                    core.hidePalette(restoreFocus: false)
                    AppLauncher.showInFinder(URL(fileURLWithPath: path))
                })
        }
        items.append(
            PopoverMenuItem(
                title: "Delete Quicklink", systemImage: "trash", shortcut: "⌘⌫",
                isDestructive: true
            ) {
                Task { await core.deleteQuicklink(id: quicklink.id) }
            })
        return PopoverMenuContent(header: quicklink.name, items: items)
    }

    private static func symbol(_ quicklink: Quicklink) -> String {
        quicklink.iconSymbol ?? QuicklinkDestination.detect(quicklink.link)?.defaultSymbol
            ?? Quicklink.sfSymbol
    }
}
