import SwiftUI

/// Quick Look inside the panel: a system preview window would take key and close the palette.
struct FileSearchQuickLook: View {

    @Environment(\.metrics) private var metrics
    let result: FileSearchResult
    let onClose: () -> Void

    /// Concentric: every corner inside the panel is the one outside it less its own inset.
    private var cardRadius: CGFloat { metrics.radius.panel - metrics.spacing.md }
    private var surfaceRadius: CGFloat { cardRadius - metrics.spacing.md }

    var body: some View {
        ZStack {
            // Only the margin dismisses: a tap over the preview belongs to its own transport.
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
            card
        }
    }

    private var card: some View {
        VStack(spacing: metrics.spacing.md) {
            QuickLookSurface(url: result.url)
                .clipShape(RoundedRectangle(cornerRadius: surfaceRadius, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: metrics.spacing.sm) {
                Text(result.name)
                    .font(metrics.typography.rowTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: metrics.spacing.lg)
                Text("Close")
                    .font(metrics.typography.bar)
                    .foregroundStyle(Theme.Colors.textSecondary)
                KeyCapChip(text: "esc", style: .outline)
            }
        }
        .padding(metrics.spacing.md)
        .frosted(in: RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
        .padding(metrics.spacing.md)
    }
}
