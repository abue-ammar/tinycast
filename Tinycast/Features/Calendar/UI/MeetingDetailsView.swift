import SwiftUI

struct MeetingDetailsView: View {
    @Environment(\.metrics) private var metrics
    let meeting: MeetingEvent
    let details: MeetingDetails

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: metrics.spacing.md) {
                header
                if let location = details.location {
                    HStack(alignment: .firstTextBaseline, spacing: metrics.spacing.sm) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text(location)
                    }
                    .font(metrics.typography.rowTitle)
                    .padding(.top, metrics.spacing.xl)
                }
                if !details.attendees.isEmpty {
                    sectionHeader(String(localized: "Attendees"))
                    ForEach(details.attendees.indices, id: \.self) { index in
                        AttendeeRow(attendee: details.attendees[index])
                    }
                }
                if let notes = details.notes {
                    sectionHeader(String(localized: "Description"))
                    Text(notes)
                        .font(metrics.typography.rowTitle)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .textSelection(.enabled)
            .padding(.horizontal, metrics.spacing.xxl)
            .padding(.top, metrics.spacing.md)
            .padding(.bottom, metrics.spacing.xxl)
            .hideNativeScrollers()
        }
        .edgeDissolve()
        .thinScrollbar()
        // A different meeting starts at its title, not wherever the last one was scrolled to.
        .id(meeting.id)
    }

    private var header: some View {
        HStack(spacing: metrics.spacing.xl) {
            SymbolImage(
                name: meeting.link?.provider.sfSymbol ?? "calendar",
                size: metrics.size.headerIconSlot
            )
            .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: metrics.spacing.xs) {
                Text(meeting.title)
                    .font(metrics.typography.calcResult.weight(.semibold))
                HStack(spacing: metrics.spacing.sm) {
                    if let tint = meeting.calendarColor { ColorDot(color: tint.color) }
                    Text(subtitle)
                        .font(metrics.typography.rowTrailing)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var subtitle: String {
        let day = UpcomingWindow.dayLabel(meeting.start, calendar: .current)
        return "\(day) · \(MeetingTimeFormat.range(of: meeting)) · \(meeting.calendarName)"
    }

    private func sectionHeader(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: metrics.spacing.xs) {
            Text(title)
                .font(metrics.typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textTertiary)
            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(height: 1)
        }
        .padding(.top, metrics.spacing.xl)
    }
}

private struct AttendeeRow: View {
    @Environment(\.metrics) private var metrics
    let attendee: MeetingDetails.Attendee

    var body: some View {
        HStack(spacing: metrics.spacing.sm) {
            Image(systemName: attendee.response.symbol)
                .foregroundStyle(attendee.response.tint)
            Text(attendee.name)
                .lineLimit(1)
            if attendee.isOrganizer {
                Text("Organizer")
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            Spacer(minLength: metrics.spacing.md)
            Text(attendee.response.label)
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .font(metrics.typography.rowTitle)
        .accessibilityElement(children: .combine)
    }
}

private extension MeetingDetails.Attendee.Response {
    var symbol: String {
        switch self {
        case .accepted: "checkmark.circle.fill"
        case .tentative: "questionmark.circle.fill"
        case .declined: "xmark.circle.fill"
        case .pending: "circle.dashed"
        }
    }

    var tint: Color {
        switch self {
        case .accepted: Theme.Colors.success
        case .tentative: Theme.Colors.warning
        case .declined: Theme.Colors.destructive
        case .pending: Theme.Colors.textTertiary
        }
    }

    var label: String {
        switch self {
        case .accepted: String(localized: "Accepted")
        case .tentative: String(localized: "Maybe")
        case .declined: String(localized: "Declined")
        case .pending: String(localized: "No response")
        }
    }
}
