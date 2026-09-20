import SwiftUI

/// A secret field with a show/hide button beside it; the caller's field style reaches inside.
struct RevealableSecureField: View {
    let title: String
    @Binding var text: String
    var prompt: Text?

    @State private var isRevealed = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Group {
                if isRevealed {
                    TextField(title, text: $text, prompt: prompt)
                } else {
                    SecureField(title, text: $text, prompt: prompt)
                }
            }
            .focused($isFocused)
            Button {
                // Swapping the field drops focus, which would send the next keystroke nowhere.
                let wasFocused = isFocused
                isRevealed.toggle()
                if wasFocused { Task { isFocused = true } }
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(isRevealed ? "Hide" : "Show")
            .disabled(text.isEmpty)
            .accessibilityLabel(isRevealed ? "Hide \(title)" : "Show \(title)")
        }
        .onChange(of: text.isEmpty) { _, isEmpty in
            if isEmpty { isRevealed = false }
        }
    }
}
