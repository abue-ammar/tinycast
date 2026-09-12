import SwiftUI

/// The sidebar's search field. Not `SettingsFilterField`: that one is borderless because it sits
/// inside a `Form` row, where a bezel would read as a control the section owns.
struct SettingsSearchField: View {
    @Binding var query: String
    @FocusState.Binding var focused: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("", text: $query, prompt: Text("Search"))
                .textFieldStyle(.plain)
                .labelsHidden()
                .focused($focused)
                .pointerStyle(.horizontalText)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(height: Theme.Size.settingsSearchField)
        // Glass on a layer of its own: `frosted` ends in `.tint(.clear)`, which would erase the caret.
        .background { Color.clear.frosted(in: Capsule()) }
        .contentShape(.rect)
        .onTapGesture { focused = true }
        .accessibilityLabel("Search settings")
    }
}
