import SwiftUI

/// The language pair over the two columns, filling the hidden search field's slot in the header.
struct TranslationHeader: View {
    let openSource: () -> Void
    let openTarget: () -> Void
    @Environment(TranslationCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                PopUpButton(
                    title: coordinator.sourceLabel, help: "Source language",
                    tooltipAlignment: .leading, tooltipEdge: .bottom, action: openSource)
                Spacer(minLength: 0)
            }
            .frame(width: seamOffset)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                PopUpButton(
                    title: coordinator.targetLabel, help: "Target language",
                    tooltipAlignment: .trailing, tooltipEdge: .bottom, action: openTarget)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// The column seam, measured inside the slot: it starts after the gutter, chevron and gap.
    private var seamOffset: CGFloat {
        let leading = metrics.spacing.md * 2 + metrics.size.headerIconSlot + metrics.spacing.xl
        return metrics.size.panelWidth / 2 - leading
    }
}

extension TranslationHeader {
    /// A header pop-up with Tinycast's own hover label; `.help()` never shows behind the panel.
    struct PopUpButton: View {
        let title: String
        var systemImage: String?
        /// The control's name for VoiceOver; the hover label repeats it unless `tooltip` says more.
        let help: String
        var tooltip: String?
        var tooltipAlignment: HorizontalAlignment = .center
        var tooltipEdge: VerticalEdge = .top
        let action: () -> Void
        @Environment(\.metrics) private var metrics

        var body: some View {
            BarButton(chrome: .rounded, action: action) {
                HStack(spacing: metrics.spacing.sm) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(
                                .system(
                                    size: metrics.scaled(Theme.Typography.menuSymbolSize),
                                    weight: Theme.Typography.menuSymbolWeight))
                    }
                    Text(title)
                        .font(metrics.typography.bar)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.down")
                        .font(metrics.typography.disclosure)
                }
                .foregroundStyle(Theme.Colors.textSecondary)
            }
            .tooltip(tooltip ?? help, alignment: tooltipAlignment, edge: tooltipEdge)
            .accessibilityLabel(help)
            .accessibilityValue(title)
        }
    }
}
