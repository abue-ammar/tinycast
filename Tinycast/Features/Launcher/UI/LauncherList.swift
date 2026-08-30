import SwiftUI

struct LauncherList: View {
    let results: [AppEntry]
    /// The flat row id the screen has selected, not an entry id: a fallback can repeat a result.
    let selectedRowID: String?
    let favoriteCount: Int
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
    /// The `Use "…" with` section, always last; nil when nothing is typed.
    var fallbacks: FallbackSection?
    @Environment(RunningAppsMonitor.self) private var runningApps

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

        var sectionTitle: String {
            switch self {
            case .calc: return "Calculator"
            case .meeting: return "Meeting"
            }
        }

        var rowID: String {
            switch self {
            case .calc: return "calc-card"
            case .meeting: return "meeting-card"
            }
        }
    }

    private enum Row: Identifiable {
        case header(String)
        /// Its own case, because only this header carries a gear.
        case fallbackHeader(String)
        case card(LeadCard)
        /// `slot` is the row's ⌘-digit, carried from the section build rather than searched.
        case app(AppEntry, slot: Character?)
        case fallback(AppEntry, index: Int)
        var id: String {
            switch self {
            case .header(let title): return "header-" + title
            case .fallbackHeader: return "fallback-header"
            case .card(let card): return card.rowID
            case .app(let app, _): return app.id
            case .fallback(let app, _): return "fallback-" + app.id
            }
        }
    }

    /// Whether the selection sits on flat index 0: the card, else the first result.
    private var firstRowSelected: Bool {
        card != nil ? cardSelected : selectedRowID != nil && selectedRowID == results.first?.id
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
            guard !results.isEmpty else { return cardRows + fallbackRows }
            return cardRows + [.header("Results")] + results.map { .app($0, slot: nil) }
                + fallbackRows
        }
        var rows: [Row] = cardRows
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
            .meeting, .application, .systemSettings, .extensionCommand, .quicklink, .snippet,
            .systemAction, .windowCommand, .customCommand, .command
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
        return rows + fallbackRows
    }

    var body: some View {
        let rows = rows
        return Group {
            if results.isEmpty && card == nil && fallbacks == nil {
                EmptyResults(text: "No apps found")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(rows) { row in
                                switch row {
                                case .header(let title):
                                    SectionHeader(title: title, isFirst: row.id == rows.first?.id)
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
                                        .padding(.bottom, Theme.Spacing.xs)
                                        .selectionFrame(cardSelected)
                                case .app(let app, let slot):
                                    AppRow(
                                        app: app,
                                        selected: app.id == selectedRowID,
                                        running: runningApps.isRunning(app),
                                        slot: slot
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture { onActivate(app) }
                                    .onRightClick { onActions(app) }
                                    .selectionFrame(app.id == selectedRowID)
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
            if let subtitle = app.subtitle {
                Text(subtitle)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
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
