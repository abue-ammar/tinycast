import SwiftUI

/// Fill and hover for every lead card, so none can answer a selection differently from another.
private struct LeadCardChrome: ViewModifier {
    let selected: Bool
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .background(shape.fill(Theme.Colors.cardFill))
            .background(shape.fill(fill))
            .armedHover($hovered)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
    }

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }
}

extension View {
    /// Padding stays each card's own: a meeting card is deliberately shorter than an answer.
    func leadCard(selected: Bool) -> some View {
        modifier(LeadCardChrome(selected: selected))
    }
}

/// One side of a two-column lead card: a value line with an optional word-name badge beneath.
struct LeadCardColumn: View {
    let text: AttributedString
    let badge: String?
    var weight: Font.Weight = .medium

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text(text)
                .font(Theme.Typography.calcResult.weight(weight))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let badge { LeadCardBadge(text: badge) }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Spacing.md)
    }
}

/// The pill a lead card states its kind in — the calculator's unit, a colour's notation.
private struct LeadCardBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Typography.keyCap)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xxs)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.keyCap, style: .continuous)
                    .fill(Theme.Colors.controlSurface)
            )
    }
}
