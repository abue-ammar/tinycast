import SwiftUI

struct CameraPreviewView: View {
    let meeting: MeetingEvent
    let now: Date
    let feed: CameraSession.Feed
    let onJoin: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            CameraStage(feed: feed)
                .frame(
                    width: Theme.Size.cameraPreview.width,
                    height: Theme.Size.cameraPreview.height)
            footer
        }
        .frame(width: Theme.Size.cameraPreview.width)
        .background(Theme.Colors.panelScrim)
        .background(GlassEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.dialog, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(meeting.title)
                    .font(Theme.Typography.rowTitle)
                    .lineLimit(1)
                Text(UpcomingWindow.countdown(to: meeting.start, now: now, locale: .current))
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: Theme.Spacing.md)
            CameraButton(
                title: String(localized: "Cancel"), keyCaps: ["esc"], emphasis: .secondary,
                onActivate: onCancel)
            CameraButton(title: String(localized: "Join"), keyCaps: ["↵"], onActivate: onJoin)
        }
        .padding(Theme.Spacing.xl)
    }
}
