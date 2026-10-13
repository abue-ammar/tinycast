import SwiftUI

struct CalendarBar: View {
    @Environment(\.metrics) private var metrics
    let color: MeetingEvent.CalendarColor?

    var body: some View {
        Capsule()
            .fill(color?.color ?? .clear)
            .frame(width: metrics.size.calendarBarWidth, height: metrics.size.calendarBarHeight)
            .accessibilityHidden(true)
    }
}

/// The range, then a countdown pill in a slot always reserved, so pills form one straight column.
struct MeetingTiming: View {
    @Environment(\.metrics) private var metrics
    let meeting: MeetingEvent
    let now: Date

    var body: some View {
        let pill = UpcomingWindow.rowPill(for: meeting, now: now, calendar: .current)
        HStack(spacing: metrics.spacing.md) {
            Text(MeetingTimeFormat.range(of: meeting))
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(meeting.isInProgress(now: now) ? .primary : .secondary)
            ZStack {
                Text(UpcomingWindow.countdown(to: now + 60 * 60, now: now)).hidden()
                Text(UpcomingWindow.dayLabel(now + 24 * 60 * 60, calendar: .current)).hidden()
                Text(pill?.text ?? "")
                    .foregroundStyle(pill?.isImminent == true ? .primary : .secondary)
            }
            .font(metrics.typography.rowTrailing.weight(.medium))
            .padding(.horizontal, metrics.spacing.sm)
            .padding(.vertical, metrics.spacing.xxs)
            .background(
                RoundedRectangle(cornerRadius: metrics.radius.keyCap, style: .continuous)
                    .fill(pill == nil ? .clear : Theme.Colors.controlSurface))
        }
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
    }
}

/// Resolves a launcher meeting entry live, so its bar and countdown never wait on a republish.
struct MeetingEntryContent<Content: View>: View {
    @Environment(CalendarStore.self) private var store
    @Environment(MeetingClock.self) private var clock
    let entryID: String
    @ViewBuilder let content: (MeetingEvent, Date) -> Content

    var body: some View {
        if let id = MeetingEvent.id(fromEntryID: entryID), let meeting = store.event(id: id) {
            content(meeting, clock.now)
        }
    }
}
