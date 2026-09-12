import SwiftUI

/// The join card above the launcher results; selectable like a row, Enter joins.
struct MeetingCard: View {
    @Environment(\.metrics) private var metrics
    let meeting: MeetingEvent
    let now: Date
    let selected: Bool

    var body: some View {
        HStack(spacing: metrics.spacing.xl) {
            SymbolImage(
                name: meeting.link?.provider.sfSymbol ?? "calendar",
                size: metrics.size.headerIconSlot
            )
            .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: metrics.spacing.xs) {
                Text(meeting.title)
                    .font(metrics.typography.calcResult.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(subtitle)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: metrics.spacing.md)
            Text(UpcomingWindow.countdown(to: meeting.start, now: now))
                .font(metrics.typography.rowTitle.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, metrics.spacing.md)
                .padding(.vertical, metrics.spacing.xxs)
                .background(
                    RoundedRectangle(cornerRadius: metrics.radius.keyCap, style: .continuous)
                        .fill(Theme.Colors.controlSurface)
                )
        }
        .padding(.horizontal, metrics.spacing.xl)
        .padding(.vertical, metrics.spacing.xxl)
        .leadCard(selected: selected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(meeting.title), \(UpcomingWindow.countdown(to: meeting.start, now: now))"
        )
        .accessibilityAddTraits(.isButton)
    }

    private var subtitle: String {
        let time = MeetingTimeFormat.clock(meeting.start)
        guard let provider = meeting.link?.provider else { return time }
        return "\(time) · \(provider.title)"
    }
}

/// The one place a meeting time becomes text, so the card and the schedule rows never diverge.
@MainActor
enum MeetingTimeFormat {
    private static let formatter: Date.FormatStyle = .dateTime.hour().minute()

    static func clock(_ date: Date) -> String { date.formatted(formatter) }
}

/// Actions for a meeting, shared by the card and every schedule row.
@MainActor
enum MeetingActionsMenu {
    static func content(meeting: MeetingEvent, core: AppCore) -> PopoverMenuContent {
        var items: [PopoverMenuItem] = []
        if meeting.link != nil {
            items.append(
                PopoverMenuItem(title: "Join Meeting", systemImage: "video.fill", shortcut: "↵") {
                    core.calendarCoordinator.join(meeting)
                })
            items.append(
                PopoverMenuItem(title: "Copy Meeting Link", systemImage: "link", shortcut: "⌘↵") {
                    core.calendarCoordinator.copyLink(meeting)
                })
        }
        items.append(
            PopoverMenuItem(
                title: "Open in Calendar", systemImage: "calendar", startsSection: true,
                shortcut: meeting.link == nil ? "↵" : nil
            ) {
                core.calendarCoordinator.openInCalendar(meeting)
            })
        return PopoverMenuContent(header: meeting.title, items: items)
    }
}
