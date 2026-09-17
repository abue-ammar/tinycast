import SwiftUI

/// The draft the New Event dialog edits; reference semantics are what let the caller read it back.
@MainActor
@Observable
final class EventDraftState {
    var draft = EventDraft()
}

struct EventDraftFields: View {
    @Environment(\.metrics) private var metrics
    @Bindable var state: EventDraftState
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.xl) {
            TextField("", text: $state.draft.title, prompt: Text("Event title"))
                .focused($focused)
                .dialogTextField()
            ChoiceRow(
                label: "Starts", values: EventDraft.startOffsets,
                title: EventDraft.label(startOffset:), selection: $state.draft.startOffsetMinutes)
            ChoiceRow(
                label: "For", values: EventDraft.durations, title: EventDraft.label(duration:),
                selection: $state.draft.durationMinutes)
        }
        .onAppear { focused = true }
    }
}

private struct ChoiceRow: View {
    @Environment(\.metrics) private var metrics
    let label: String
    let values: [Int]
    let title: (Int) -> String
    @Binding var selection: Int
    @State private var hoveredValue: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            Text(label)
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize()

            HStack(spacing: 0) {
                ForEach(values, id: \.self) { value in
                    Button {
                        selection = value
                    } label: {
                        Text(title(value))
                            .font(metrics.typography.rowTrailing)
                            .foregroundStyle(
                                selection == value
                                    ? Theme.Colors.textPrimary : Theme.Colors.textSecondary
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: metrics.size.dialogButtonHeight)
                            .contentShape(Rectangle())
                            .background(
                                RoundedRectangle(
                                    cornerRadius: metrics.radius.row, style: .continuous
                                )
                                .fill(fill(for: value)))
                    }
                    .buttonStyle(.plain)
                    .onHover { hoveredValue = $0 ? value : nil }
                    .accessibilityLabel(title(value))
                    .accessibilityAddTraits(
                        selection == value ? [.isButton, .isSelected] : .isButton)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                    .fill(Theme.Colors.controlSurface))
        }
    }

    private func fill(for value: Int) -> Color {
        if selection == value { return Theme.Colors.selection }
        if hoveredValue == value { return Theme.Colors.rowHover }
        return .clear
    }
}
