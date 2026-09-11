import SwiftUI

/// The draft the New Event dialog edits; reference semantics are what let the caller read it back.
@MainActor
@Observable
final class EventDraftState {
    var draft = EventDraft()
}

/// The New Event dialog's controls: a title, then when and how long, as chips.
struct EventDraftFields: View {
    @Environment(\.metrics) private var metrics
    @Bindable var state: EventDraftState
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.xl) {
            TextField("", text: $state.draft.title, prompt: Text("Event title"))
                .textFieldStyle(.plain)
                .labelsHidden()
                .font(metrics.typography.rowTitle)
                .focused($focused)
                .padding(.horizontal, metrics.spacing.lg)
                .frame(height: metrics.size.barButtonHeight)
                .background(
                    RoundedRectangle(cornerRadius: metrics.radius.menu, style: .continuous)
                        .fill(Theme.Colors.controlSurface))
            ChipRow(
                label: "Starts", values: EventDraft.startOffsets,
                title: EventDraft.label(startOffset:), selection: $state.draft.startOffsetMinutes)
            ChipRow(
                label: "For", values: EventDraft.durations, title: EventDraft.label(duration:),
                selection: $state.draft.durationMinutes)
        }
        .onAppear { focused = true }
    }
}

/// Our own chips: a menu-style `Picker` drops an AppKit popover onto a vibrancy surface.
private struct ChipRow: View {
    @Environment(\.metrics) private var metrics
    let label: String
    let values: [Int]
    let title: (Int) -> String
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: metrics.spacing.md) {
            Text(label)
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: metrics.size.dialogIcon, alignment: .leading)
            ForEach(values, id: \.self) { value in
                Chip(title: title(value), selected: value == selection) { selection = value }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct Chip: View {

    @Environment(\.metrics) private var metrics
    let title: String
    let selected: Bool
    let onTap: () -> Void
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return Theme.Colors.controlSurface
    }

    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(selected ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                .padding(.horizontal, metrics.spacing.lg)
                .frame(height: metrics.size.barButtonHeight)
                .contentShape(Capsule())
                .background(Capsule().fill(fill))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
