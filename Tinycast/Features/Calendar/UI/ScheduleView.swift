import SwiftUI

/// The My Schedule list, bucketed into Today and Tomorrow.
struct ScheduleList: View {
    @Environment(\.metrics) private var metrics
    let results: [MeetingEvent]
    let selectedID: MeetingEvent.ID?
    let now: Date
    let scroll: ScrollIntent
    let onActivate: (MeetingEvent) -> Void
    let onActions: (MeetingEvent) -> Void

    private enum Row: Identifiable {
        case header(String)
        case meeting(MeetingEvent)
        var id: String {
            switch self {
            case .header(let title): return "header-" + title
            case .meeting(let meeting): return meeting.id
            }
        }
    }

    /// `results` is already in start order, so a bucket change is where a header belongs.
    private var rows: [Row] {
        var rows: [Row] = []
        var current: String?
        for meeting in results {
            let title =
                MeetingDay(for: meeting.start, now: now, calendar: .current)?.title ?? "Later"
            if title != current {
                rows.append(.header(title))
                current = title
            }
            rows.append(.meeting(meeting))
        }
        return rows
    }

    private var firstRowSelected: Bool {
        selectedID != nil && selectedID == results.first?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        switch row {
                        case .header(let title):
                            SectionHeader(title: title, isFirst: row.id == rows.first?.id)
                        case .meeting(let meeting):
                            MeetingRow(
                                meeting: meeting, now: now, selected: meeting.id == selectedID
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { onActivate(meeting) }
                            .onRightClick { onActions(meeting) }
                            .selectionFrame(meeting.id == selectedID)
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
                scroll, row: selectedID, atOrigin: firstRowSelected, proxy: proxy)
        }
    }
}

private struct MeetingRow: View {

    @Environment(\.metrics) private var metrics
    let meeting: MeetingEvent
    let now: Date
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            SymbolImage(
                name: meeting.link?.provider.sfSymbol ?? "calendar", size: metrics.size.rowIcon * 0.7
            )
            .frame(width: metrics.size.rowIcon, height: metrics.size.rowIcon)
            .foregroundStyle(meeting.isInProgress(now: now) ? Theme.Colors.brand : .secondary)
            Text(meeting.title)
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
            Spacer(minLength: metrics.spacing.md)
            Text(trailing)
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(meeting.title), \(trailing)")
        .accessibilityAddTraits(.isButton)
    }

    /// A meeting under way says so; everything else reads as the clock time it starts.
    private var trailing: String {
        meeting.isInProgress(now: now) ? "Now" : MeetingTimeFormat.clock(meeting.start)
    }
}
