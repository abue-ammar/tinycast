import SwiftUI

/// A colour entry's preview: the colour and the copied text, the notations being ⌘K's business.
struct ColorPreview: View {
    @Environment(\.metrics) private var metrics
    let color: ColorValue
    let text: String

    /// Fixed at any pane width: stretched edge to edge a sample reads as a background.
    private static let swatchSize = CGSize(width: 220, height: 130)

    var body: some View {
        VStack(spacing: metrics.spacing.lg) {
            ColorSwatch(color: color, cornerRadius: metrics.radius.card)
                .frame(width: Self.swatchSize.width, height: Self.swatchSize.height)
            Text(text)
                .font(.system(.subheadline, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, metrics.spacing.xxl)
    }
}
