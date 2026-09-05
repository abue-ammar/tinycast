import SwiftUI

/// A drawn caret: the one field editor belongs to the search field, not to these controls.
struct ExtensionCaret: View {
    @State private var visible = true

    var body: some View {
        RoundedRectangle(cornerRadius: 0.5, style: .continuous)
            .fill(Theme.Colors.textPrimary)
            .frame(width: ExtensionFormMetrics.caretWidth)
            .frame(height: ExtensionFormMetrics.caretHeight)
            .opacity(visible ? 1 : 0)
            // AppKit's own blink rate, so a drawn caret and a real one keep time together.
            .animation(
                .easeInOut(duration: 0.1).repeatForever().delay(ExtensionFormMetrics.caretBlink),
                value: visible
            )
            .onAppear { visible = false }
            .accessibilityHidden(true)
    }
}
