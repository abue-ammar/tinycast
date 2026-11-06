import SwiftUI

struct LauncherList: View {

    @Environment(\.metrics) private var metrics
    let results: [AppEntry]
    /// The flat row id the screen has selected, not an entry id: a fallback can repeat a result.
    let selectedRowID: String?
    let favorites: [FavoritesStore.Item]
    let meetingCount: Int
    let suggestionCount: Int
    let matchCount: Int
    /// Changes only when the list should scroll, so mouse selection never yanks it.
    let scroll: ScrollIntent
    /// The card at flat index 0, when one leads. At most one ever does.
    var card: LeadCard?
    var cardSelected = false
    var onActivateCard: () -> Void = {}
    var onCardActions: () -> Void = {}
    let onActivate: (AppEntry) -> Void
    let onActions: (AppEntry) -> Void
    let onActivateFavorite: (Int) -> Void
    let onFavoriteActions: (Int) -> Void
    let onDropped: () -> Void
    var files: FileSection?
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

    struct FileSection {
        let results: [FileSearchResult]
        let onActivate: (Int) -> Void
        let onActions: (Int) -> Void
    }

    /// Calc answers a typed query and the card an empty one, so only one ever leads.
    enum LeadCard: Equatable {
        case calc(CalcResult)
        case meeting(MeetingEvent, now: Date)
        case color(ColorValue)

        var sectionTitle: String {
            switch self {
            case .calc: return String(localized: "Calculator")
            case .meeting: return String(localized: "Meeting")
            case .color: return String(localized: "Color")
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
        /// Its own case, because only this header carries a gear.
        case fallbackHeader(String)
        case card(LeadCard)
        case app(AppEntry)
        case favorite(FavoritesStore.Item, index: Int)
        case file(FileSearchResult, index: Int)
        case fallback(AppEntry, index: Int)
        var id: String {
            switch self {
            case .header(let title): return "header-" + title
            case .fallbackHeader: return "fallback-header"
            case .card(let card): return card.rowID
            case .app(let app): return app.id
            case .favorite(let favorite, _): return favorite.id
            case .file(let result, _): return "file-" + result.id
            case .fallback(let app, _): return "fallback-" + app.id
            }
        }
    }

    private var firstRowSelected: Bool {
        if card != nil { return cardSelected }
        return selectedRowID != nil && selectedRowID == (favorites.first?.id ?? results.first?.id)
    }

    private var fileRows: [Row] {
        guard let files else { return [] }
        return [.header(String(localized: "Files"))]
            + files.results.enumerated().map { Row.file($1, index: $0) }
    }

    /// Every row the fallback section contributes, always after the results.
    private var fallbackRows: [Row] {
        guard let fallbacks else { return [] }
        return [.fallbackHeader(fallbacks.title)]
            + fallbacks.entries.enumerated().map { Row.fallback($1, index: $0) }
    }

    private var rows: [Row] {
        var rows: [Row] = []
        if let card { rows = [.header(card.sectionTitle), .card(card)] }
        let meetings = results.prefix(meetingCount)
        let suggestions = results.dropFirst(meetingCount).prefix(suggestionCount)
        let pinnedCount = meetingCount + suggestionCount
        let matches = results.dropFirst(pinnedCount).prefix(matchCount)
        let rest = results.dropFirst(pinnedCount + matchCount)
        var grouped: [AppEntry.Kind: [AppEntry]] = [:]
        for app in rest { grouped[app.kind, default: []].append(app) }
        if !favorites.isEmpty {
            rows.append(.header(String(localized: "Favorites")))
            rows.append(
                contentsOf: favorites.enumerated().map {
                    .favorite($1, index: $0)
                })
        }
        if !meetings.isEmpty {
            rows.append(.header(AppEntry.Kind.meeting.descriptor.sectionTitle.resolved()))
            rows.append(contentsOf: meetings.map { .app($0) })
        }
        if !suggestions.isEmpty {
            rows.append(.header(String(localized: "Suggestions")))
            rows.append(contentsOf: suggestions.map { .app($0) })
        }
        if !matches.isEmpty {
            rows.append(.header(String(localized: "Results")))
            rows.append(contentsOf: matches.map { .app($0) })
        }
        // Publication order, so rows match the flat index.
        let kinds: [AppEntry.Kind] = [
            .meeting, .application, .systemSettings, .extensionCommand, .quicklink, .appleShortcut,
            .snippet, .systemAction, .windowLayout, .windowRoom, .windowCommand, .customCommand,
            .quickAction, .command
        ]
        for kind in kinds {
            guard let group = grouped[kind], !group.isEmpty else { continue }
            rows.append(.header(kind.descriptor.sectionTitle.resolved()))
            rows.append(contentsOf: group.map { .app($0) })
        }
        // A missing kind would make every later row activate its neighbour: assert instead.
        assert(
            grouped.keys.allSatisfy(kinds.contains),
            "kind missing from the launcher's section order: "
                + grouped.keys.filter { !kinds.contains($0) }.map(\.rawValue).joined(separator: ", "))
        return rows + fileRows + fallbackRows
    }

    var body: some View {
        let rows = rows
        return Group {
            if results.isEmpty && favorites.isEmpty && card == nil && files == nil && fallbacks == nil {
                EmptyResults(text: String(localized: "No apps found"))
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
                                        configureHelp: String(localized: "Configure Fallbacks…"))
                                case .card(let card):
                                    LeadCardView(card: card, selected: cardSelected)
                                        .contentShape(Rectangle())
                                        .onTapGesture(perform: onActivateCard)
                                        .onRightClick(perform: onCardActions)
                                        .padding(.bottom, metrics.spacing.xs)
                                        .selectionFrame(cardSelected)
                                case .app(let app):
                                    AppRow(
                                        app: app,
                                        selected: app.id == selectedRowID,
                                        running: runningApps.isRunning(app),
                                        slot: nil
                                    )
                                    .contentShape(Rectangle())
                                    .onRowTap(drag: drag(for: app)) { onActivate(app) }
                                    .onRightClick { onActions(app) }
                                    .selectionFrame(app.id == selectedRowID)
                                case .favorite(let favorite, let index):
                                    favoriteRow(favorite, index: index)
                                        .contentShape(Rectangle())
                                        .onRowTap(drag: drag(for: favorite)) { onActivateFavorite(index) }
                                        .onRightClick { onFavoriteActions(index) }
                                        .selectionFrame(favorite.id == selectedRowID)
                                case .file(let result, let index):
                                    FileSearchRow(
                                        result: result, selected: row.id == selectedRowID,
                                        showsLocation: true
                                    )
                                    .contentShape(Rectangle())
                                    .onRowTap(drag: result.rowDrag(dropped: onDropped)) {
                                        files?.onActivate(index)
                                    }
                                    .onRightClick { files?.onActions(index) }
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

    @ViewBuilder
    private func favoriteRow(_ favorite: FavoritesStore.Item, index: Int) -> some View {
        let slot = FavoriteSlots.digit(at: index)
        switch favorite {
        case .entry(let entry):
            AppRow(
                app: entry, selected: favorite.id == selectedRowID,
                running: runningApps.isRunning(entry), slot: slot)
        case .file(let file):
            FileSearchRow(
                result: file, selected: favorite.id == selectedRowID,
                showsLocation: true, slot: slot)
        }
    }

    private func drag(for favorite: FavoritesStore.Item) -> RowDrag? {
        switch favorite {
        case .entry(let entry): drag(for: entry)
        case .file(let file): file.rowDrag(dropped: onDropped)
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

    private var shortcutCaps: [String]? {
        guard let action = app.hotKeyAction else { return nil }
        return hotKeys.binding(for: action)?.keycaps
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            AppIconView(app: app, pointSize: metrics.size.resultRowIcon)
                .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
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
