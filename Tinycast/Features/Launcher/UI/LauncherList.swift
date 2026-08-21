import SwiftUI

struct LauncherList: View {
    let results: [AppEntry]
    let selectedID: AppEntry.ID?
    let favoriteCount: Int
    let showSections: Bool
    /// Changes only when the list should scroll, so mouse selection never yanks it.
    let scroll: ScrollIntent
    /// The inline answer, at flat index 0 when present; needs a non-empty query.
    var calc: CalcResult?
    var calcSelected = false
    var onActivateCalc: () -> Void = {}
    var onCalcActions: () -> Void = {}
    let onActivate: (AppEntry) -> Void
    let onActions: (AppEntry) -> Void
    @Environment(RunningAppsMonitor.self) private var runningApps

    private nonisolated static let calcRowID = "calc-card"

    private enum Row: Identifiable {
        case header(String)
        case calc(CalcResult)
        /// `slot` is the row's ⌘-digit, carried from the section build so no row has to search for it.
        case app(AppEntry, slot: Character?)
        var id: String {
            switch self {
            case .header(let title): return "header-" + title
            case .calc: return LauncherList.calcRowID
            case .app(let app, _): return app.id
            }
        }
    }

    /// Scroll target for the current selection.
    private var selectedRowID: String? { calcSelected ? Self.calcRowID : selectedID }

    /// Whether the selection sits on flat index 0: the calc card, else the first result.
    private var firstRowSelected: Bool {
        calc != nil ? calcSelected : selectedID != nil && selectedID == results.first?.id
    }

    private var rows: [Row] {
        var calcRows: [Row] = []
        if let calc { calcRows = [.header("Calculator"), .calc(calc)] }
        guard showSections else {
            guard !results.isEmpty else { return calcRows }
            return calcRows + [.header("Results")] + results.map { .app($0, slot: nil) }
        }
        var rows: [Row] = calcRows
        let favorites = results.prefix(favoriteCount)
        let rest = results.dropFirst(favoriteCount)
        var grouped: [AppEntry.Kind: [AppEntry]] = [:]
        for app in rest { grouped[app.kind, default: []].append(app) }
        if !favorites.isEmpty {
            rows.append(.header("Favorites"))
            rows.append(
                contentsOf: favorites.enumerated().map {
                    .app($1, slot: FavoriteSlots.digit(at: $0))
                })
        }
        // Publication order, so rows match the flat index.
        let kinds: [AppEntry.Kind] = [
            .application, .systemSettings, .extensionCommand, .quicklink, .snippet,
            .systemAction, .windowCommand, .customCommand, .aiTransform, .command
        ]
        for kind in kinds {
            guard let group = grouped[kind], !group.isEmpty else { continue }
            rows.append(.header(kind.descriptor.sectionTitle))
            rows.append(contentsOf: group.map { .app($0, slot: nil) })
        }
        // A kind missing from `kinds` doesn't just hide its rows — every row after it in the flat
        // index would then activate its neighbour. Cheap to assert, silent and confusing to debug.
        assert(
            grouped.keys.allSatisfy(kinds.contains),
            "kind missing from the launcher's section order: "
                + grouped.keys.filter { !kinds.contains($0) }.map(\.rawValue).joined(separator: ", "))
        return rows
    }

    var body: some View {
        let rows = rows
        return Group {
            if results.isEmpty && calc == nil {
                EmptyResults(text: "No apps found")
            } else {
                ScrollViewReader { proxy in
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
                                        .selectionFrame(calcSelected)
                                case .app(let app, let slot):
                                    AppRow(
                                        app: app,
                                        selected: app.id == selectedID,
                                        running: runningApps.isRunning(app),
                                        slot: slot
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture { onActivate(app) }
                                    .onRightClick { onActions(app) }
                                    .selectionFrame(app.id == selectedID)
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
                    // Snap to the origin on the first row so its header shows too.
                    .scrollFollowsSelection(
                        scroll, row: selectedRowID, atOrigin: firstRowSelected, proxy: proxy)
                }
            }
        }
    }
}

private struct AppRow: View {
    let app: AppEntry
    let selected: Bool
    let running: Bool
    /// This row's ⌘-digit, or nil for a row no chord launches.
    let slot: Character?
    /// Observed so a hotkey set/cleared in Settings re-renders the row's keycaps immediately.
    @Environment(HotKeyManager.self) private var hotKeys
    /// Observed for the same reason: an alias edit re-renders the row's badge at once.
    @Environment(AliasStore.self) private var aliases
    /// Observed here rather than up in the list, so a ⌘ press re-renders rows and not the palette.
    @Environment(PaletteState.self) private var palette
    @State private var hovered = false

    /// Selection wins over hover when a row is both; otherwise hover shows its fainter layer.
    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    /// Keycaps for this entry's hotkey, or `nil` if none is bound.
    private var shortcutCaps: [String]? {
        guard let action = app.hotKeyAction else { return nil }
        return hotKeys.binding(for: action)?.keycaps
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            AppIconView(app: app)
                .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
                .overlay(alignment: .bottom) {
                    if running {
                        Circle()
                            .fill(.secondary)
                            .frame(width: 3, height: 3)
                            .offset(y: 3)
                    }
                }
            Text(app.name)
                .font(Theme.Typography.rowTitle)
                .lineLimit(1)
            if let alias = aliases.alias(for: app.preferenceKey) {
                Text(alias)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xxs)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                            .fill(Theme.Colors.controlSurface))
            }
            if let caps = shortcutCaps {
                HStack(spacing: Theme.Spacing.xxs) {
                    ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in
                        KeyCapChip(text: cap, style: .outline)
                    }
                }
            }
            Spacer()
            // Holding ⌘ turns the trailing label into the chord that launches this row.
            if let slot, palette.commandHeld {
                HStack(spacing: Theme.Spacing.xxs) {
                    KeyCapChip(text: "⌘", style: .outline)
                    KeyCapChip(text: String(slot), style: .outline)
                }
            } else {
                Text(app.kindLabel)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(.secondary)
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
