import AppKit
import SwiftUI

/// A secret field with a show/hide button beside it; the caller's field style reaches inside.
struct RevealableSecureField: View {
    let title: String
    @Binding var text: String
    var prompt: Text?

    @State private var isRevealed = false
    @State private var carriedSelection: NSRange?
    @FocusState private var focusedField: Field?

    private enum Field { case secure, plain }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if isRevealed {
                TextField(title, text: $text, prompt: prompt)
                    .autocorrectionDisabled()
                    .writingToolsBehavior(.disabled)
                    .focused($focusedField, equals: .plain)
            } else {
                SecureField(title, text: $text, prompt: prompt)
                    .focused($focusedField, equals: .secure)
            }
            Button {
                setRevealed(!isRevealed)
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
        .onChange(of: focusedField) { _, field in
            guard field != nil, let selection = carriedSelection else { return }
            carriedSelection = nil
            restore(selection)
        }
    }

    /// Where keystrokes go, and this control's only while it is editing `text`.
    private var fieldEditor: NSTextView? {
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isFieldEditor,
            editor.string == text
        else { return nil }
        return editor
    }

    private func setRevealed(_ revealed: Bool) {
        let wasFocused = focusedField != nil
        carriedSelection = wasFocused ? fieldEditor?.selectedRange() : nil
        isRevealed = revealed
        // Swapping the field drops focus; naming the new one moves it there instead.
        if wasFocused { focusedField = revealed ? .plain : .secure }
    }

    /// AppKit selects the whole field as it takes focus, so the next keystroke would replace it.
    private func restore(_ selection: NSRange) {
        guard let editor = fieldEditor, NSMaxRange(selection) <= (editor.string as NSString).length
        else { return }
        editor.setSelectedRange(selection)
        editor.scrollRangeToVisible(selection)
    }
}
