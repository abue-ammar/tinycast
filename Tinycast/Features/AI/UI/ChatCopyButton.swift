import SwiftUI

struct ChatCopyButton: View {
    @Environment(\.locale) private var localizationLocale
    let text: String
    var subject = String(localized: "Message", bundle: .appLanguage)

    /// The stamp is the copy event: a fresh one re-arms the reset, so a second tap holds the check.
    @State private var copiedAt: Date?

    private var copied: Bool { copiedAt != nil }

    var body: some View {
        Button {
            Paster.copyPlainText(text)
            copiedAt = Date()
        } label: {
            Image(systemName: copied ? "checkmark" : "square.on.square")
                .font(Theme.Typography.keyCap)
                .foregroundStyle(tint)
                .frame(width: Theme.Size.chatMessageAction, height: Theme.Size.chatMessageAction)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copied ? String(
            localized: "Copied",
            bundle: .appLanguage) : String(
            localized: "Copy \(subject)",
            bundle: .appLanguage))
        .task(id: copiedAt) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(Theme.Duration.copyFeedback))
            copiedAt = nil
        }
    }

    private var tint: Color {
        if copied { return Theme.Colors.success }
        return Theme.Colors.textSecondary
    }
}
