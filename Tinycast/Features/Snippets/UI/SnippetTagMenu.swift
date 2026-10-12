import SwiftUI

@MainActor
enum SnippetTagMenu {
    static func content(coordinator: SnippetCoordinator) -> PopoverMenuContent {
        let selected = coordinator.tagFilter.selectedIDs
        let all = PopoverMenuItem(
            title: "All Tags", icon: .symbol("tag"),
            accessory: AnyView(Checkmark(checked: selected.isEmpty))
        ) { coordinator.toggleTag(nil) }
        let tags = coordinator.tags.enumerated().map { index, tag in
            PopoverMenuItem(
                title: tag.name, icon: .symbol("circle.fill"), startsSection: index == 0,
                iconTint: tag.color.tint,
                accessory: AnyView(Checkmark(checked: selected.contains(tag.id)))
            ) { coordinator.toggleTag(tag.id) }
        }
        return PopoverMenuContent(items: [all] + tags)
    }

    private struct Checkmark: View {
        let checked: Bool
        @Environment(\.metrics) private var metrics
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            Image(systemName: "checkmark.app")
                .foregroundStyle(Color.clear, Theme.Colors.border)
                .overlay {
                    if reduceMotion {
                        check.opacity(checked ? 1 : 0)
                    } else {
                        check.symbolEffect(.drawOff, isActive: !checked)
                    }
                }
                .symbolRenderingMode(.palette)
                .font(.system(size: metrics.scaled(Theme.Typography.checkboxSymbolSize), weight: .light))
                .accessibilityLabel(checked ? "Selected" : "Not selected")
        }

        private var check: some View {
            Image(systemName: "checkmark.app")
                .foregroundStyle(Theme.Colors.textPrimary, Color.clear)
                .accessibilityHidden(true)
        }
    }
}
