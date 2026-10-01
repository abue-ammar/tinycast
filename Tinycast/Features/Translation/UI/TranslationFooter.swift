import SwiftUI

/// The bottom bar's controls for the translator: the app menu, the service, Copy and Actions.
struct TranslationFooter<MenuButton: View>: View {
    let menuButton: MenuButton
    let toggleService: () -> Void
    let toggleActions: () -> Void
    @Environment(TranslationCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics

    var body: some View {
        // Floating controls, no bar: the launcher's own geometry, drawn on the same surface.
        HStack(spacing: 0) {
            menuButton
            serviceButton
                .padding(.leading, metrics.spacing.md)
                // Never wider than the menu it opens, so a long model name truncates before Copy.
                .frame(maxWidth: metrics.size.menuWidth, alignment: .leading)
            Spacer(minLength: metrics.spacing.md)
            actionGroup
        }
        .padding(.horizontal, metrics.spacing.md)
        .frame(height: metrics.size.bottomBarHeight)
        .frame(maxWidth: .infinity)
    }

    private var serviceButton: some View {
        TranslationHeader.PopUpButton(
            title: coordinator.serviceLabel,
            systemImage: coordinator.settings.provider == .ai ? "sparkles" : "translate",
            help: "Translation service", tooltip: coordinator.serviceLabel,
            tooltipAlignment: .leading, action: toggleService)
    }

    /// Copy and Actions share one glass capsule, as the launcher's primary action and ⌘K do.
    private var actionGroup: some View {
        let canCopy = coordinator.canCopy
        return HStack(spacing: metrics.spacing.xxs) {
            BarButton(action: { coordinator.copyTranslation() }) {
                HStack(spacing: metrics.spacing.sm) {
                    Text("Copy Translation")
                        .font(metrics.typography.bar)
                        .foregroundStyle(.primary)
                    HStack(spacing: metrics.spacing.xxs) {
                        KeyCapChip(text: "⌘", style: .outline)
                        KeyCapChip(text: "↵", style: .outline)
                    }
                }
                .opacity(canCopy ? 1 : 0.45)
            }
            .disabled(!canCopy)
            .allowsHitTesting(canCopy)
            .accessibilityLabel("Copy Translation")
            BarButton(action: toggleActions) {
                HStack(spacing: metrics.spacing.sm) {
                    Text("Actions")
                        .font(metrics.typography.bar)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    HStack(spacing: metrics.spacing.xxs) {
                        KeyCapChip(text: "⌘", style: .outline)
                        KeyCapChip(text: "K", style: .outline)
                    }
                }
            }
            .accessibilityLabel("Actions")
        }
        .padding(metrics.spacing.xs)
        .frosted(in: Capsule())
    }
}
