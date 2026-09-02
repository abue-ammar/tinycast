import SwiftUI

/// The join card above the launcher results; selectable like a row, Enter joins.
struct MeetingCard: View {
    let meeting: MeetingEvent
    let now: Date
    let selected: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.xl) {
            SymbolImage(
                name: meeting.link?.provider.sfSymbol ?? "calendar",
                size: Theme.Size.headerIconSlot
            )
            .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(meeting.title)
                    .font(Theme.Typography.calcResult.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(subtitle)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.md)
            Text(UpcomingWindow.countdown(to: meeting.start, now: now))
                .font(Theme.Typography.rowTitle.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xxs)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.keyCap, style: .continuous)
                        .fill(Theme.Colors.controlSurface)
                )
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.xxl)
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
                title: "Open in Calendar", systemImage: "calendar",
                shortcut: meeting.link == nil ? "↵" : nil
            ) {
                core.calendarCoordinator.openInCalendar(meeting)
            })
        return PopoverMenuContent(header: meeting.title, items: items)
    }
}
