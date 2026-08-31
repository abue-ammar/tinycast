import SwiftUI

/// Shown only on request: a Settings pane gets screenshotted, and this is what names a person.
struct RedactedText: View {
    let value: String
    var revealHelp = "Click to reveal"
    var hideHelp = "Click to hide"

    @State private var isRevealed = false

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: Theme.Duration.enter)) { isRevealed.toggle() }
        } label: {
            Text(isRevealed ? value : RedactedPlaceholder.forValue(value))
                .monospaced()
                .lineLimit(1)
                .truncationMode(.middle)
                .blur(radius: isRevealed ? 0 : Theme.Blur.redaction)
                .textSelection(.disabled)
        }
        .buttonStyle(.plain)
        .help(isRevealed ? hideHelp : revealHelp)
        // Reading a disguise aloud is worse than useless to someone who cannot see the blur.
        .accessibilityLabel(isRevealed ? value : "Hidden: \(revealHelp.lowercased())")
        .accessibilityAddTraits(.isButton)
    }
}
