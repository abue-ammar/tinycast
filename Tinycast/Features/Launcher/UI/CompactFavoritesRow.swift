import SwiftUI

/// Overflow is a button rather than a slot, so no favorite loses its digit to it.
struct CompactFavoritesRow: View {
    let favorites: [AppEntry]
    let showsOverflow: Bool
    let onLaunch: (AppEntry) -> Void
    let onOverflow: () -> Void
    @Environment(\.metrics) private var metrics

    var body: some View {
        HStack(spacing: metrics.spacing.xs) {
            // Identified by the app, so a reorder moves an icon with its app, not by position.
            ForEach(Array(favorites.enumerated()), id: \.element.id) { index, app in
                CompactFavoriteButton(help: help(for: app, at: index)) {
                    onLaunch(app)
                } content: {
                    AppIconView(app: app, pointSize: metrics.size.rowIcon)
                        .frame(width: metrics.size.rowIcon, height: metrics.size.rowIcon)
                }
            }
            if showsOverflow {
                CompactFavoriteButton(help: "Show all  ↓", action: onOverflow) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: metrics.size.rowIcon, height: metrics.size.rowIcon)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Theme.Colors.controlSurface)
                                .padding(metrics.spacing.xxs)
                        )
                }
            }
        }
    }

    private func help(for app: AppEntry, at index: Int) -> String {
        guard let digit = FavoriteSlots.digit(at: index) else { return app.name }
        return "\(app.name)  ⌘\(digit)"
    }
}

/// One compact favorite: bare icon, tooltip, action; no hover chrome, so it reads tight.
private struct CompactFavoriteButton<Content: View>: View {
    let help: String
    let action: () -> Void
    @ViewBuilder let content: Content
    @Environment(\.metrics) private var metrics

    var body: some View {
        Button(action: action) {
            content
                .contentShape(RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
