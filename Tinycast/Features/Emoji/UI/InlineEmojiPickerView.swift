import SwiftUI

struct InlineEmojiPickerView: View {
    @Environment(InlineEmojiCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings
    @Environment(\.metrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.xs) {
            HStack {
                Text(
                    coordinator.query.isEmpty
                        ? settings.inlineEmojiSuggestions.title : ":" + coordinator.query
                )
                .lineLimit(1)
                Spacer(minLength: metrics.spacing.md)
                Text(verbatim: "esc")
            }
            .font(metrics.typography.rowTrailing)
            .foregroundStyle(Theme.Colors.textSecondary)
            .padding(.horizontal, metrics.spacing.md)
            .padding(.vertical, metrics.spacing.xs)

            if coordinator.entries.isEmpty {
                Text(emptyMessage)
                    .font(metrics.typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(metrics.spacing.md)
            } else {
                ForEach(Array(coordinator.entries.enumerated()), id: \.element.id) { index, entry in
                    Button {
                        coordinator.select(index)
                        coordinator.insertSelection()
                    } label: {
                        HStack(spacing: metrics.spacing.md) {
                            Text(verbatim: entry.display(tone: settings.emojiSkinTone))
                                .font(.system(size: metrics.size.menuIcon))
                                .frame(width: metrics.size.menuIcon)
                            Text(entry.displayName)
                                .font(metrics.typography.rowTitle)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if coordinator.selection == index {
                                Text(verbatim: "↵")
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                        .padding(metrics.spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                        .background(
                            coordinator.selection == index ? Theme.Colors.selection : .clear,
                            in: RoundedRectangle(cornerRadius: metrics.radius.menuRow, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(entry.displayName)
                    .accessibilityAddTraits(coordinator.selection == index ? [.isSelected] : [])
                    .onHover { if $0 { coordinator.select(index) } }
                }
            }
        }
        .padding(metrics.spacing.sm)
        .frame(width: metrics.size.menuWidth, alignment: .leading)
        .background(GlassEffectView())
        .clipShape(RoundedRectangle(cornerRadius: metrics.radius.menuPanel, style: .continuous))
        .motionScope()
    }

    private var emptyMessage: String {
        guard coordinator.query.isEmpty else { return String(localized: "No results") }
        return settings.inlineEmojiSuggestions == .pinned
            ? String(localized: "Pin emoji in the full picker, or type to search.")
            : String(localized: "Type to search for your first emoji.")
    }
}
