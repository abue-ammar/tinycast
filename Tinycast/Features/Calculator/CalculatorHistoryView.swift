import SwiftUI

/// Full-width list of past calculations, mirroring `ClipboardList`'s structure; each row carries both sides of the calculation, so there's no preview pane.
struct CalculatorHistoryList: View {
    let results: [CalcHistoryEntry]
    let selectedID: CalcHistoryEntry.ID?
    /// Changes only when the list should scroll (keyboard nav / reset), so mouse selection never yanks the scroll position.
    let scroll: ScrollIntent
    /// Live answer for a calculation typed into the history search — same card and flat-index-0 contract as the launcher (`LauncherList.calc`).
    var calc: CalcResult?
    var calcSelected = false
    var onActivateCalc: () -> Void = {}
    var onCalcActions: () -> Void = {}
    let onSelect: (CalcHistoryEntry) -> Void
    let onActivate: () -> Void
    let onActions: (CalcHistoryEntry) -> Void

    private nonisolated static let calcRowID = "calc-card"

    private enum Row: Identifiable {
        case header(String)
        case calc(CalcResult)
        case entry(CalcHistoryEntry)
        var id: String {
            switch self {
            case .header(let title): return "header-" + title
            case .calc: return CalculatorHistoryList.calcRowID
            case .entry(let entry): return entry.id.uuidString
            }
        }
    }

    /// Scroll target for the current selection.
    private var selectedRowID: String? {
        calcSelected ? Self.calcRowID : selectedID?.uuidString
    }

    /// Whether the selection sits on flat index 0 — the calc card when present, else the first entry.
    private var firstRowSelected: Bool {
        calc != nil ? calcSelected : selectedID != nil && selectedID == results.first?.id
    }

    /// Entries are newest-first, so grouping walks and emits a date header whenever the bucket changes (same as the clipboard list); a live calculation pins above them.
    private var rows: [Row] {
        var rows: [Row] = []
        if let calc { rows = [.header("Calculator"), .calc(calc)] }
        var currentBucket: DateBucket?
        for entry in results {
            let bucket = DateBucket(for: entry.createdAt)
            if bucket != currentBucket {
                rows.append(.header(bucket.title))
                currentBucket = bucket
            }
            rows.append(.entry(entry))
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
                        case .calc(let result):
                            CalculatorCard(result: result, selected: calcSelected)
                                .contentShape(Rectangle())
                                .onTapGesture(perform: onActivateCalc)
                                .onRightClick(perform: onCalcActions)
                                .padding(.bottom, Theme.Spacing.xs)
                        case .entry(let entry):
                            CalcHistoryRow(entry: entry, selected: entry.id == selectedID)
                                .contentShape(Rectangle())
                                .onTapGesture { onSelect(entry) }
                                .simultaneousGesture(
                                    TapGesture(count: 2).onEnded {
                                        onSelect(entry)
                                        onActivate()
                                    }
                                )
                                .onRightClick { onActions(entry) }
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
                    // On the first row, snap to the origin so its section header shows too — a nil anchor won't, since the row is already visible.
                    if firstRowSelected {
                        proxy.scrollToOrigin()
                    } else if let selectedRowID {
                        proxy.reveal(selectedRowID)
                    }
                }
            }
        }
    }
}

private struct CalcHistoryRow: View {
    let entry: CalcHistoryEntry
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
                    Image(systemName: "plus.forwardslash.minus")
                        .font(.system(size: 12))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                )
            Text(entry.expression)
                .font(Theme.Typography.rowTitle)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: Theme.Spacing.xl)
            Text(entry.result)
                .font(Theme.Typography.rowTitle.weight(.semibold))
                .lineLimit(1)
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

/// Actions menu content for a calculator-history entry, shown bottom-right like the other modes.
@MainActor
enum CalcHistoryActionsMenu {
    static func content(entry: CalcHistoryEntry, core: AppCore, calcHistory: CalculatorHistoryStore)
        -> PopoverMenuContent {
        PopoverMenuContent(
            header: entry.expression,
            items: [
                PopoverMenuItem(title: "Copy Answer", systemImage: "doc.on.doc", shortcut: "↵") {
                    core.copyHistoryEntry(entry)
                },
                PopoverMenuItem(
                    title: "Copy Expression", systemImage: "doc.on.doc.fill", shortcut: "⌘↵"
                ) {
                    core.copyHistoryExpression(entry)
                },
                PopoverMenuItem(title: "Delete Entry", systemImage: "trash", isDestructive: true) {
                    calcHistory.remove(entry)
                },
                PopoverMenuItem(
                    title: "Delete All Entries", systemImage: "trash.fill", isDestructive: true
                ) {
                    calcHistory.clearAll()
                }
            ]
        )
    }
}
