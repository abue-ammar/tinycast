import AppKit
import SwiftUI

/// A suffixed numeric field. Holds its own text, commits on ↵ or focus loss, reverts on Escape.
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
                .onChange(of: isFocused) { _, focused in if !focused { commit() } }
                .onChange(of: value) { _, new in if !isFocused { text = String(new) } }
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

    /// A number outside the range clamps and shows the clamped value; nonsense reverts.
    private func commit() {
        guard let typed = Int(text.trimmingCharacters(in: .whitespaces)) else { return revert() }
        let clamped = min(max(typed, range.lowerBound), range.upperBound)
        text = String(clamped)
        onCommit(clamped)
    }

    private func revert() {
        text = String(value)
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
