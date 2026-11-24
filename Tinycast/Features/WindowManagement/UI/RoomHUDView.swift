import SwiftUI

/// The message pill's shape, naming its subject instead of a tone: the room and its apps.
struct RoomHUDView: View {
    let name: String
    let appURLs: [URL]
    @Environment(\.metrics) private var metrics

    var body: some View {
        HStack(spacing: metrics.spacing.md) {
            Image(systemName: Room.sfSymbol)
                .font(metrics.typography.menuIcon)
                .foregroundStyle(Color.primary)
                .frame(width: metrics.size.menuIcon, height: metrics.size.menuIcon)
                .accessibilityHidden(true)
            Text(name)
                .font(metrics.typography.bar)
                .foregroundStyle(Color.primary)
                .lineLimit(1)
            if !appURLs.isEmpty {
                HStack(spacing: metrics.spacing.xs) {
                    ForEach(appURLs, id: \.self) { url in
                        EntryIconView(source: .file(stamp: FileIconStamp.value(for: url)), fileURL: url)
                            .frame(width: metrics.size.menuIcon, height: metrics.size.menuIcon)
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, metrics.spacing.xl)
        .padding(.vertical, metrics.spacing.lg)
        .frame(maxWidth: metrics.size.hudMaxWidth, alignment: .leading)
        .fixedSize()
        .background(Theme.Colors.panelScrim)
        .background(GlassEffectView())
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
    }
}
