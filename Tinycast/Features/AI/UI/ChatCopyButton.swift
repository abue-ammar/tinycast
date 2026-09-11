import SwiftUI

struct ChatCopyButton: View {

    @Environment(\.metrics) private var metrics
    let text: String
    var subject = "Message"

    /// The stamp is the copy event: a fresh one re-arms the reset, so a second tap holds the check.
    @State private var copiedAt: Date?

    private var copied: Bool { copiedAt != nil }

    var body: some View {
        Button {
            Paster.copyPlainText(text)
            copiedAt = Date()
        } label: {
            Image(systemName: copied ? "checkmark" : "square.on.square")
                .font(metrics.typography.keyCap)
                .foregroundStyle(tint)
                .frame(width: metrics.size.chatMessageAction, height: metrics.size.chatMessageAction)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copied ? "Copied" : "Copy \(subject)")
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
