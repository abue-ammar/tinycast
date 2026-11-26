import AppKit
import SwiftUI

struct RevealableSecureField: View {
    let title: String
    @Binding var text: String
    var prompt: Text?
    var allowsRevealWhenEmpty = false
    var focusTint: Color?
    var revealIconWeight: Font.Weight?

    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.isEnabled) private var isEnabled
    @State private var isRevealed = false
    @State private var carriedSelection: NSRange?
    @FocusState private var focusedField: Field?

    private enum Field { case secure, plain }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Group {
                if isRevealed {
                    TextField(title, text: $text, prompt: prompt)
                        .autocorrectionDisabled()
                        .writingToolsBehavior(.disabled)
                        .focused($focusedField, equals: .plain)
                } else {
                    SecureField(title, text: $text, prompt: prompt)
                        .focused($focusedField, equals: .secure)
                }
            }
            .focusEffectDisabled(focusTint != nil)
            .overlay {
                if let focusTint, focusedField != nil, appearsActive, isEnabled {
                    RoundedRectangle(cornerRadius: Theme.Radius.roundedTextField)
                        .strokeBorder(focusTint, lineWidth: Theme.Size.focusRingStroke)
                        .padding(-Theme.Size.hairline)
                        .allowsHitTesting(false)
                }
            }
            Button {
                setRevealed(!isRevealed)
            } label: {
                let icon = Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
                if let revealIconWeight {
                    icon.fontWeight(revealIconWeight)
                } else {
                    icon
                }
            }
            .buttonStyle(.plain)
            .help(isRevealed ? "Hide" : "Show")
            .disabled(text.isEmpty && !allowsRevealWhenEmpty)
            .accessibilityLabel(isRevealed ? "Hide \(title)" : "Show \(title)")
        }
        .onChange(of: text.isEmpty) { _, isEmpty in
            if isEmpty, isRevealed, !allowsRevealWhenEmpty { setRevealed(false) }
        }
        .onChange(of: focusedField) { _, field in
            guard field != nil else { return }
            if let focusTint { fieldEditor?.insertionPointColor = NSColor(focusTint) }
            guard let selection = carriedSelection else { return }
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
