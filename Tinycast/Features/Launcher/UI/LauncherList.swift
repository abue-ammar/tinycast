import SwiftUI

struct LauncherList: View {

    @Environment(\.metrics) private var metrics
    let results: [AppEntry]
    /// The flat row id the screen has selected, not an entry id: a fallback can repeat a result.
    let selectedRowID: String?
    let favoriteCount: Int
    let suggestionCount: Int
    let showSections: Bool
    /// Changes only when the list should scroll, so mouse selection never yanks it.
    let scroll: ScrollIntent
    /// The card at flat index 0, when one leads. At most one ever does.
    var card: LeadCard?
    var cardSelected = false
    var onActivateCard: () -> Void = {}
    var onCardActions: () -> Void = {}
    let onActivate: (AppEntry) -> Void
    let onActions: (AppEntry) -> Void
    let onDropped: () -> Void
    /// Returned only for an unmatched query, before the ordinary fuzzy results.
    var choices: ChoiceSection?
    /// The `Use "…" with` section, always last; nil when nothing is typed.
    var fallbacks: FallbackSection?
    @Environment(RunningAppsMonitor.self) private var runningApps

    struct ChoiceSection {
        let entries: [AppEntry]
        let onActivate: (Int) -> Void
    }

    /// What the fallback section draws and where its rows go, addressed by position.
    struct FallbackSection {
        let title: String
        let entries: [AppEntry]
        let onActivate: (Int) -> Void
        let onActions: (Int) -> Void
        let onConfigure: () -> Void
    }

    /// Calc answers a typed query and the card an empty one, so only one ever leads.
    enum LeadCard: Equatable {
        case calc(CalcResult)
        case meeting(MeetingEvent, now: Date)
        case color(ColorValue)

        var sectionTitle: String {
            switch self {
            case .calc: return "Calculator"
            case .meeting: return "Meeting"
            case .color: return "Color"
            }
        }

        var rowID: String {
            switch self {
            case .calc: return "calc-card"
            case .meeting: return "meeting-card"
            case .color: return "color-card"
            }
        }
    }

    private enum Row: Identifiable {
        case header(String)
        case choiceHeader
        /// Its own case, because only this header carries a gear.
        case fallbackHeader(String)
        case card(LeadCard)
        /// `slot` is the row's ⌘-digit, carried from the section build rather than searched.
        case app(AppEntry, slot: Character?)
        case choice(AppEntry, index: Int)
        case fallback(AppEntry, index: Int)
        var id: String {
            switch self {
            case .header(let title): return "header-" + title
            case .choiceHeader: return "natural-choice-header"
            case .fallbackHeader: return "fallback-header"
            case .card(let card): return card.rowID
            case .app(let app, _): return app.id
            case .choice(let app, _): return "natural-choice-" + app.id
            case .fallback(let app, _): return "fallback-" + app.id
            }
        }
    }

    /// Whether the selection sits on flat index 0: the card, else the first result.
    private var firstRowSelected: Bool {
        if let first = choices?.entries.first {
            return selectedRowID == "natural-choice-" + first.id
        }
        return card != nil ? cardSelected : selectedRowID != nil && selectedRowID == results.first?.id
    }

    private var choiceRows: [Row] {
        guard let choices, !choices.entries.isEmpty else { return [] }
        return [.choiceHeader]
            + choices.entries.enumerated().map { Row.choice($1, index: $0) }
    }

    /// Every row the fallback section contributes, always after the results.
    private var fallbackRows: [Row] {
        guard let fallbacks else { return [] }
        return [.fallbackHeader(fallbacks.title)]
            + fallbacks.entries.enumerated().map { Row.fallback($1, index: $0) }
    }

    private var rows: [Row] {
        var cardRows: [Row] = []
        if let card { cardRows = [.header(card.sectionTitle), .card(card)] }
        guard showSections else {
            guard !results.isEmpty else { return choiceRows + cardRows + fallbackRows }
            return choiceRows + cardRows + [.header("Results")] + results.map { .app($0, slot: nil) }
                + fallbackRows
        }
        var rows: [Row] = cardRows
        let favorites = results.prefix(favoriteCount)
        let suggestions = results.dropFirst(favoriteCount).prefix(suggestionCount)
        let rest = results.dropFirst(favoriteCount + suggestionCount)
        var grouped: [AppEntry.Kind: [AppEntry]] = [:]
        for app in rest { grouped[app.kind, default: []].append(app) }
        if !favorites.isEmpty {
            rows.append(.header("Favorites"))
            rows.append(
                contentsOf: favorites.enumerated().map {
                    .app($1, slot: FavoriteSlots.digit(at: $0))
                })
        }
        if !suggestions.isEmpty {
            rows.append(.header("Suggestions"))
            rows.append(contentsOf: suggestions.map { .app($0, slot: nil) })
        }
        // Publication order, so rows match the flat index.
        let kinds: [AppEntry.Kind] = [
            .meeting, .application, .systemSettings, .extensionCommand, .quicklink, .appleShortcut,
            .snippet, .systemAction, .windowLayout, .windowCommand, .customCommand, .quickAction,
            .command
        ]
        for kind in kinds {
            guard let group = grouped[kind], !group.isEmpty else { continue }
            rows.append(.header(kind.descriptor.sectionTitle))
            rows.append(contentsOf: group.map { .app($0, slot: nil) })
        }
        // A missing kind would make every later row activate its neighbour: assert instead.
        assert(
            grouped.keys.allSatisfy(kinds.contains),
            "kind missing from the launcher's section order: "
                + grouped.keys.filter { !kinds.contains($0) }.map(\.rawValue).joined(separator: ", "))
        return choiceRows + rows + fallbackRows
    }

    var body: some View {
        let rows = rows
        return Group {
            if results.isEmpty && card == nil && choices == nil && fallbacks == nil {
                EmptyResults(text: "No apps found")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(rows) { row in
                                switch row {
                                case .header(let title):
                                    SectionHeader(title: title, isFirst: row.id == rows.first?.id)
                                case .choiceHeader:
                                    SectionHeader(title: "TypeSafe Suggestions", isFirst: row.id == rows.first?.id)
                                case .fallbackHeader(let title):
                                    SectionHeader(
                                        title: title, isFirst: row.id == rows.first?.id,
                                        configure: fallbacks?.onConfigure,
                                        configureHelp: "Configure Fallbacks…")
                                case .card(let card):
                                    LeadCardView(card: card, selected: cardSelected)
                                        .contentShape(Rectangle())
                                        .onTapGesture(perform: onActivateCard)
                                        .onRightClick(perform: onCardActions)
                                        .padding(.bottom, metrics.spacing.xs)
                                        .selectionFrame(cardSelected)
                                case .app(let app, let slot):
                                    AppRow(
                                        app: app,
                                        selected: app.id == selectedRowID,
                                        running: runningApps.isRunning(app),
                                        slot: slot
                                    )
                                    .contentShape(Rectangle())
                                    .onRowTap(drag: drag(for: app)) { onActivate(app) }
                                    .onRightClick { onActions(app) }
                                    .selectionFrame(app.id == selectedRowID)
                                case .choice(let app, let index):
                                    AppRow(
                                        app: app, selected: row.id == selectedRowID, running: false,
                                        slot: nil
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture { choices?.onActivate(index) }
                                    .selectionFrame(row.id == selectedRowID)
                                case .fallback(let app, let index):
                                    AppRow(
                                        app: app, selected: row.id == selectedRowID, running: false,
                                        slot: nil
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture { fallbacks?.onActivate(index) }
                                    .onRightClick { fallbacks?.onActions(index) }
                                    .selectionFrame(row.id == selectedRowID)
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
                    // Snap to the origin on the first row so its header shows too.
                    .scrollFollowsSelection(
                        scroll, row: selectedRowID, atOrigin: firstRowSelected, proxy: proxy)
                }
            }
        }
    }

    /// Cache-only icon: the row holds its own smaller bitmap, and a decode would stall the drag.
    private func drag(for app: AppEntry) -> RowDrag? {
        guard app.canDragOut else { return nil }
        return RowDrag(
            item: { .file(app.url, image: IconCache.cached(app.iconSource, fileURL: app.url)) },
            dropped: onDropped)
    }
}

/// Draws whichever card leads; each feature still owns how its own card looks.
private struct LeadCardView: View {
    let card: LauncherList.LeadCard
    let selected: Bool

    var body: some View {
        switch card {
        case .calc(let result):
            CalculatorCard(result: result, selected: selected)
        case .meeting(let meeting, let now):
            MeetingCard(meeting: meeting, now: now, selected: selected)
        case .color(let color):
            ColorCard(color: color, selected: selected)
        }
    }
}

private struct AppRow: View {

    @Environment(\.metrics) private var metrics
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
        HStack(spacing: metrics.spacing.lg) {
            AppIconView(app: app, pointSize: metrics.size.rowIcon)
                .frame(width: metrics.size.rowIcon, height: metrics.size.rowIcon)
                .overlay(alignment: .bottom) {
                    if running {
                        Circle()
                            .fill(.secondary)
                            .frame(width: 3, height: 3)
                            .offset(y: 3)
                    }
                }
            if app.kind == .meeting {
                MeetingEntryContent(entryID: app.id) { meeting, _ in
                    CalendarBar(color: meeting.calendarColor)
                }
            }
            Text(app.name)
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
            if let subtitle = app.subtitle {
                Text(subtitle)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let alias = aliases.alias(for: app.preferenceKey) {
                Text(alias)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, metrics.spacing.sm)
                    .padding(.vertical, metrics.spacing.xxs)
                    .background(
                        RoundedRectangle(cornerRadius: metrics.radius.menu, style: .continuous)
                            .fill(Theme.Colors.controlSurface))
            }
            if let caps = shortcutCaps {
                HStack(spacing: metrics.spacing.xxs) {
                    ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in
                        KeyCapChip(text: cap, style: .outline)
                    }
                }
            }
            Spacer()
            if let refresh = app.backgroundRefresh {
                ExtensionRefreshIndicator(state: refresh)
                    .font(metrics.typography.rowTrailing)
            }
            // Holding ⌘ turns the trailing label into the chord that launches this row.
            if let slot, palette.commandHeld {
                HStack(spacing: metrics.spacing.xxs) {
                    KeyCapChip(text: "⌘", style: .outline)
                    KeyCapChip(text: String(slot), style: .outline)
                }
            } else if app.kind == .meeting {
                MeetingEntryContent(entryID: app.id) { MeetingTiming(meeting: $0, now: $1) }
            } else {
                Text(app.kindLabel)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
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
