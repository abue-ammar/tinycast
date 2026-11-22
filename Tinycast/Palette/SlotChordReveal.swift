import SwiftUI

/// A row's trailing label, traded for its ⌘-digit chord while ⌘ is held.
struct SlotChordReveal<Label: View>: View {
    let slot: Character?
    @ViewBuilder let label: Label
    /// Read here, not in the row, so a ⌘ press re-renders only this trailing slot.
    @Environment(PaletteState.self) private var palette
    @Environment(\.metrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let revealed = slot != nil && palette.commandHeld
        ZStack(alignment: .trailing) {
            if revealed, let slot {
                HStack(spacing: metrics.spacing.xxs) {
                    KeyCapChip(text: "⌘", style: .outline)
                    KeyCapChip(text: String(slot), style: .outline)
                }
                .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            } else {
                label.transition(.opacity)
            }
        }
        // Only the reveal animates: a release or a chord clears the chords at once.
        .animation(revealed ? Theme.SlotChordMotion.reveal : nil, value: revealed)
    }
}

extension SlotChordReveal where Label == EmptyView {
    init(slot: Character?) {
        self.init(slot: slot) { EmptyView() }
    }
}
