import SwiftUI

/// Lines soft-wrap: a second scroll view would fight the transcript's own dissolve.
struct MarkdownCodeView: View {
    let language: String?
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.md) {
                if let language {
                    Text(language)
                        .font(Theme.Typography.keyCap)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                Spacer(minLength: 0)
                ChatCopyButton(text: text, subject: "Code")
            }
            Text(text)
                .font(Theme.Typography.code)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(Theme.Colors.cardStroke))
    }
}
