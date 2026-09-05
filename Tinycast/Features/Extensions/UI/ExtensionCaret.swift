import SwiftUI

/// A drawn caret: the one field editor belongs to the search field, not to these controls.
struct ExtensionCaret: View {
    @State private var visible = true
    /// Stepped by a timer, because a repeating animation fades where AppKit's caret switches.
    private let blink = Timer.publish(
        every: ExtensionFormMetrics.caretBlink, on: .main, in: .common
    ).autoconnect()

    var body: some View {
        RoundedRectangle(cornerRadius: 0.5, style: .continuous)
            .fill(Theme.Colors.textPrimary)
            .frame(width: ExtensionFormMetrics.caretWidth)
            .frame(height: ExtensionFormMetrics.caretHeight)
            .opacity(visible ? 1 : 0)
            // AppKit's own blink rate, so a drawn caret and a real one keep time together.
            .onReceive(blink) { _ in visible.toggle() }
            .accessibilityHidden(true)
    }
}

/// The text a control-with-list is searched by: caret at the insertion point, prompt after it.
struct ExtensionQueryText: View {
    let query: String
    let prompt: String

    var body: some View {
        HStack(spacing: 0) {
            if !query.isEmpty {
                Text(query)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            ExtensionCaret()
            if query.isEmpty {
                // After the caret, exactly as an empty field's prompt sits after its own.
                Text(prompt)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
                    .padding(.leading, ExtensionFormMetrics.caretPromptGap)
            }
        }
    }
}
