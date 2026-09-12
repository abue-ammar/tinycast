import QuickLookUI
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
        // Everything the preview itself doesn't take dismisses it, the way a light box does.
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
    }
}

private struct QuickLookSurface: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        // Arrow-keying the list must not start a movie, and the panel outlives one preview.
        view.autostarts = false
        view.shouldCloseWithWindow = false
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        guard view.previewItem as? URL != url else { return }
        view.previewItem = url as NSURL
    }

    /// The preview holds its decoder open until it is closed, and this is the last chance.
    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        view.close()
    }
}
