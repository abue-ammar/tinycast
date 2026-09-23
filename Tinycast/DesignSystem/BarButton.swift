import SwiftUI

/// AppKit resolves the named base symbol directly, without inheriting a button variant.
private struct HeaderMenuSymbol: View {
    let name: String
    let size: CGFloat

    var body: some View {
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
        if let image = NSImage(
            systemSymbolName: SystemSymbolName.resolve(name), accessibilityDescription: nil
        )?
        .withSymbolConfiguration(configuration) {
            Image(nsImage: image)
                .renderingMode(.template)
                .frame(width: size, height: size)
        }
    }
}

/// A bar control's hover chrome; footer pills and header pop-ups share `barControl` as one family.
enum BarButtonChrome {
    case capsule
    case rounded

    func shape(_ metrics: InterfaceMetrics) -> AnyShape {
        switch self {
        case .capsule:
            return AnyShape(Capsule())
        case .rounded:
            return AnyShape(
                RoundedRectangle(cornerRadius: metrics.radius.barControl, style: .continuous))
        }
    }
}

/// A palette bar control, bare until hover; hover lives here so its owner never re-renders.
struct BarButton<Label: View>: View {
    var chrome: BarButtonChrome = .capsule
    var isSelected = false
    /// `sm` padding, so a 16-point glyph frame makes a square as tall as the bar.
    var isCompact = false
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovered = false
    @Environment(\.metrics) private var metrics

    var body: some View {
        let shape = chrome.shape(metrics)
        return Button(action: action) {
            label
                .padding(.horizontal, isCompact ? metrics.spacing.sm : metrics.spacing.md)
                .frame(height: metrics.size.barButtonHeight)
                .contentShape(shape)
                .background(shape.fill(fill))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }

    /// Selection beats hover, the rule every row follows.
    private var fill: Color {
        if isSelected { return Theme.Colors.selection }
        return hovered ? Theme.Colors.rowHover : Color.clear
    }
}

/// A header control that states the active choice and opens an in-window menu.
struct HeaderMenuButton: View {
    let title: String
    let icon: PopoverMenuIcon
    /// A symbol's point size before scaling; a menu beside a brand mark matches the mark instead.
    let symbolSize: CGFloat
    let isOpen: Bool
    let help: String
    let action: () -> Void
    @Environment(\.metrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: String, icon: PopoverMenuIcon, symbolSize: CGFloat = Theme.Typography.menuSymbolSize,
        isOpen: Bool, help: String, action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.symbolSize = symbolSize
        self.isOpen = isOpen
        self.help = help
        self.action = action
    }

    init(
        title: String, systemImage: String, symbolSize: CGFloat = Theme.Typography.menuSymbolSize,
        isOpen: Bool, help: String, action: @escaping () -> Void
    ) {
        self.init(
            title: title, icon: .symbol(systemImage), symbolSize: symbolSize, isOpen: isOpen,
            help: help, action: action)
    }

    var body: some View {
        BarButton(chrome: .rounded, action: action) {
            HStack(spacing: metrics.spacing.sm) {
                switch icon {
                case .blank:
                    EmptyView()
                case .symbol(let name):
                    HeaderMenuSymbol(name: name, size: metrics.scaled(symbolSize))
                case .asset(let name):
                    Image(name)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: metrics.size.barBrandIcon, height: metrics.size.barBrandIcon)
                case .file(let path):
                    MenuFileIcon(path: path)
                case .thumbnail(let id, let data):
                    MenuThumbnail(id: id, data: data)
                }
                Text(title)
                    .font(metrics.typography.bar)
                    .lineLimit(1)
                    .truncationMode(.middle)
                // One glyph rotates rather than swapping, so opening the menu cannot shift the layout.
                Image(systemName: "chevron.down")
                    .font(metrics.typography.disclosure)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                    .animation(reduceMotion ? nil : Theme.MenuMotion.chevronAnimation, value: isOpen)
            }
            .foregroundStyle(Theme.Colors.textSecondary)
        }
        .help(help)
    }
}
