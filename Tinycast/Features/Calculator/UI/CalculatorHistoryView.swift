import SwiftUI

/// Past calculations, shaped like `ClipboardList`; both sides per row, so no preview pane.
struct CalculatorHistoryList: View {
    @Environment(\.metrics) private var metrics
    let results: [CalcHistoryEntry]
    let selectedID: CalcHistoryEntry.ID?
    /// Changes only when the list should scroll, so mouse selection never yanks the position.
    let scroll: ScrollIntent
    /// Live answer typed into the history search; same flat-index-0 contract as the launcher.
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

    /// Whether the selection sits on flat index 0: the calc card, else the first entry.
    private var firstRowSelected: Bool {
        calc != nil ? calcSelected : selectedID != nil && selectedID == results.first?.id
    }

    /// Newest-first, so a date header is emitted whenever the bucket changes.
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
                                .padding(.bottom, metrics.spacing.xs)
                                .selectionFrame(calcSelected)
                        case .entry(let entry):
                            CalcHistoryRow(entry: entry, selected: entry.id == selectedID)
                                .selectionFrame(entry.id == selectedID)
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
                .padding(.horizontal, metrics.spacing.md)
                .padding(.top, metrics.spacing.xs)
                .padding(.bottom, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            // Snap to the origin on the first row so its section header shows too.
            .scrollFollowsSelection(
                scroll, row: selectedRowID, atOrigin: firstRowSelected, proxy: proxy)
        }
    }
}

private struct CalcHistoryRow: View {

    @Environment(\.metrics) private var metrics
    let entry: CalcHistoryEntry
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            RoundedRectangle(cornerRadius: metrics.radius.thumbnail, style: .continuous)
                .fill(Theme.Colors.controlSurface)
                .frame(width: metrics.size.rowIcon, height: metrics.size.rowIcon)
                .overlay(
                    Image(systemName: "plus.forwardslash.minus")
                        .font(.system(size: 12))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                )
            Text(entry.expression)
                .font(metrics.typography.rowTitle)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: metrics.spacing.xl)
            Text(entry.result)
                .font(metrics.typography.rowTitle.weight(.semibold))
                .lineLimit(1)
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
