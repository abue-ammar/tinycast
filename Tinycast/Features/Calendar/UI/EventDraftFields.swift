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
                .focused($focused)
                .dialogTextField()
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
                DialogChip(title: title(value), selected: value == selection) { selection = value }
            }
            Spacer(minLength: 0)
        }
    }
}
