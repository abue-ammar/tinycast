import SwiftUI

/// Colour-codes the label beside it; decorative, so hidden from VoiceOver.
struct ColorDot: View {
    @Environment(\.metrics) private var metrics
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: metrics.size.colorDot, height: metrics.size.colorDot)
            .accessibilityHidden(true)
    }
}
