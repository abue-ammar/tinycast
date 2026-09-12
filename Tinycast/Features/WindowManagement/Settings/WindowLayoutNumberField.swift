import AppKit
import SwiftUI

/// A suffixed numeric field. Commits every valid keystroke, clamps on ↵ or focus loss.
struct WindowLayoutNumberField: View {
    let label: String
    /// The accessibility label's subject, since "W" reads as a letter.
    let name: String
    let suffix: String
    let range: ClosedRange<Int>
    let value: Int
    let onCommit: (Int) -> Void

    @State private var text: String
    @FocusState private var isFocused: Bool

    init(
        label: String, name: String, suffix: String, range: ClosedRange<Int>, value: Int,
        onCommit: @escaping (Int) -> Void
    ) {
        self.label = label
        self.name = name
        self.suffix = suffix
        self.range = range
        self.value = value
        self.onCommit = onCommit
        _text = State(initialValue: String(value))
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(label)
                .font(Theme.Typography.keyCap)
                .foregroundStyle(Theme.Colors.textTertiary)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .monospacedDigit()
                .focused($isFocused)
                .focusEffectDisabled()
                .onSubmit(commit)
                .onExitCommand(perform: revert)
                .onChange(of: text) { _, typed in commitIfValid(typed) }
                .onChange(of: isFocused) { _, focused in if !focused { commit() } }
                .onChange(of: value) { _, new in if number(text) != new { text = String(new) } }
            Divider()
                .frame(height: Theme.Spacing.xl)
            Text(suffix)
                .font(Theme.Typography.keyCap)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: Theme.Size.layoutFieldUnit, alignment: .leading)
        }
        .layoutFieldChrome(isFocused: isFocused)
        .accessibilityLabel(name)
        .accessibilityValue("\(value) \(suffix)")
    }

    /// Live, so the preview tracks typing and ⌘↵ cannot save behind a value still in the field.
    private func commitIfValid(_ typed: String) {
        guard let typed = number(typed), range.contains(typed) else { return }
        onCommit(typed)
    }

    /// A number outside the range clamps and shows the clamped value; nonsense reverts.
    private func commit() {
        guard let typed = number(text) else { return revert() }
        let clamped = min(max(typed, range.lowerBound), range.upperBound)
        text = String(clamped)
        onCommit(clamped)
    }

    private func revert() {
        text = String(value)
    }

    private func number(_ text: String) -> Int? {
        Int(text.trimmingCharacters(in: .whitespaces))
    }
}

extension View {
    /// The inspector's one control surface, so a field, a dropdown and the add button match.
    func layoutFieldChrome(isFocused: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.barControl, style: .continuous)
        return padding(.horizontal, Theme.Spacing.md)
            .frame(height: Theme.Size.layoutControlHeight)
            .background(shape.fill(Theme.Colors.cardFill))
            .overlay(shape.stroke(isFocused ? Color.accentColor : Theme.Colors.cardStroke))
            .contentShape(shape)
    }
}
