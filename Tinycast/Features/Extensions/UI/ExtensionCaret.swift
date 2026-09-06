import SwiftUI

/// A drawn caret: the one field editor belongs to the search field, not to these controls.
struct ExtensionCaret: View {
    /// Restarted from here on every edit, so typing shows the caret as a field editor does.
    let phase: Date

    var body: some View {
        // Driven by the timeline, not a stored timer: a `body` per keystroke would restart one.
        TimelineView(.periodic(from: phase, by: ExtensionFormMetrics.caretBlink)) { context in
            RoundedRectangle(cornerRadius: 0.5, style: .continuous)
                .fill(Theme.Colors.textPrimary)
                .frame(width: ExtensionFormMetrics.caretWidth)
                .frame(height: ExtensionFormMetrics.caretHeight)
                .opacity(Self.isLit(context.date, from: phase) ? 1 : 0)
        }
        .accessibilityHidden(true)
    }

    /// AppKit's own rate: lit for the first half of each period, dark for the second.
    private static func isLit(_ now: Date, from phase: Date) -> Bool {
        let period = ExtensionFormMetrics.caretBlink * 2
        let elapsed = now.timeIntervalSince(phase).truncatingRemainder(dividingBy: period)
        return elapsed < ExtensionFormMetrics.caretBlink
    }
}

/// The text a control-with-list is searched by; the caret overlays the insertion point.
struct ExtensionQueryText: View {
    let query: String
    let prompt: String
    /// Bumped by the control whenever the query changes, which relights the caret.
    let phase: Date

    var body: some View {
        // No slot of its own: a field editor's caret sits over the text's edge, not beside it.
        Text(query.isEmpty ? prompt : query)
            .font(Theme.Typography.rowTitle)
            .foregroundStyle(query.isEmpty ? Theme.Colors.textTertiary : Theme.Colors.textPrimary)
            .lineLimit(1)
            .truncationMode(.head)
            .overlay(alignment: query.isEmpty ? .leading : .trailing) {
                ExtensionCaret(phase: phase)
                    .offset(x: query.isEmpty ? -ExtensionFormMetrics.caretPromptGap : 0)
            }
    }
}
