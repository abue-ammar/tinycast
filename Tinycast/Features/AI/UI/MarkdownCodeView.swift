import SwiftUI

/// Lines soft-wrap: a second scroll view would fight the transcript's own dissolve.
struct MarkdownCodeView: View {
    @Environment(\.metrics) private var metrics
    let language: String?
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            HStack(spacing: metrics.spacing.md) {
                if let language {
                    Text(language)
                        .font(metrics.typography.keyCap)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                Spacer(minLength: 0)
                ChatCopyButton(text: text, subject: "Code")
            }
            Text(text)
                .font(metrics.typography.code)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, metrics.spacing.xl)
        .padding(.vertical, metrics.spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
                .fill(Theme.Colors.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
                .stroke(Theme.Colors.cardStroke))
    }
}
