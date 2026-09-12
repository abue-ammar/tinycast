import SwiftUI

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
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovered = false
    @Environment(\.metrics) private var metrics

    var body: some View {
        let shape = chrome.shape(metrics)
        return Button(action: action) {
            label
                .padding(.horizontal, metrics.spacing.md)
                .frame(height: metrics.size.barButtonHeight)
                .contentShape(shape)
                .background(shape.fill(hovered ? Theme.Colors.rowHover : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

/// A header control that states the active choice and opens an in-window menu.
struct HeaderMenuButton: View {
    let title: String
    let icon: PopoverMenuIcon
    let isOpen: Bool
    let help: String
    let action: () -> Void
    @Environment(\.metrics) private var metrics

    init(
        title: String, icon: PopoverMenuIcon, isOpen: Bool, help: String,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isOpen = isOpen
        self.help = help
        self.action = action
    }

    init(
        title: String, systemImage: String, isOpen: Bool, help: String,
        action: @escaping () -> Void
    ) {
        self.init(title: title, icon: .symbol(systemImage), isOpen: isOpen, help: help, action: action)
    }

    var body: some View {
        BarButton(chrome: .rounded, action: action) {
            HStack(spacing: metrics.spacing.sm) {
                switch icon {
                case .blank:
                    EmptyView()
                case .symbol(let name):
                    Image(systemName: name)
                        .font(metrics.typography.bar)
                        .symbolRenderingMode(.hierarchical)
                case .asset(let name):
                    Image(name)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: metrics.size.barBrandIcon, height: metrics.size.barBrandIcon)
                case .file(let path):
                    MenuFileIcon(path: path)
                }
                Text(title)
                    .font(metrics.typography.bar)
                    .lineLimit(1)
                    .truncationMode(.middle)
                // Points at the menu it opens, the way a native pop-up's chevron does.
                Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                    .font(metrics.typography.disclosure)
            }
            .foregroundStyle(Theme.Colors.textSecondary)
        }
        .help(help)
    }
}
