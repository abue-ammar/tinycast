import SwiftUI

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

    private var rows: [Row] {
        MeetingDayGroup.grouping(results, now: now, calendar: .current).flatMap { group in
            [.header(group.day.title(calendar: .current))] + group.meetings.map(Row.meeting)
        }
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
                name: meeting.link?.provider.sfSymbol ?? "calendar", size: metrics.size.resultRowIcon * 0.7
            )
            .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
            .foregroundStyle(meeting.isInProgress(now: now) ? Theme.Colors.brand : .secondary)
            CalendarBar(color: meeting.calendarColor)
            Text(meeting.title)
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
            Spacer(minLength: metrics.spacing.md)
            MeetingTiming(meeting: meeting, now: now)
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityText: String {
        let parts = [
            meeting.title, MeetingTimeFormat.range(of: meeting),
            UpcomingWindow.rowPill(for: meeting, now: now, calendar: .current)?.text,
            meeting.calendarName
        ]
        return parts.compactMap(\.self).joined(separator: ", ")
    }
}
