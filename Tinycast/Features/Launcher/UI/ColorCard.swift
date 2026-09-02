import SwiftUI

/// The launcher's colour card, built from the calculator card's parts so it reads as one answer.
struct ColorCard: View {
    let color: ColorValue
    let selected: Bool

    /// Wide enough to read as a sample, narrow enough not to read as the card's background.
    private static let swatchWidth: CGFloat = 108

    /// Stated and copied as one notation, so ↵ never yields a colour the card didn't show.
    private var primary: ColorFormat { ColorFormat.primary(for: color) }

    var body: some View {
        HStack(spacing: 0) {
            LeadCardColumn(
                text: AttributedString(primary.string(for: color)), badge: primary.title)
            Image(systemName: "arrow.right")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.tertiary)
            // Stretched to the value column rather than sized: no notation is a fixed height.
            ColorSwatch(color: color, cornerRadius: Theme.Radius.card)
                .frame(width: Self.swatchWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, Theme.Spacing.md)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.xxxl)
        .leadCard(selected: selected)
    }
}

/// Actions for the colour card: the header carries the verb, so each row is just its notation.
@MainActor
enum ColorActionsMenu {
    static func content(color: ColorValue, core: AppCore) -> PopoverMenuContent {
        let primary = ColorFormat.primary(for: color)
        return PopoverMenuContent(
            header: "Copy Color as…",
            items: ColorFormat.offered(for: color).map { format in
                PopoverMenuItem(
                    title: format.title, icon: .blank,
                    shortcut: format == primary ? "↵" : nil, detail: format.string(for: color)
                ) {
                    core.clipboardCoordinator.copyColor(color, as: format)
                }
            })
    }
}
