import SwiftUI

/// The clipboard header's type filter control: it states the active filter and toggles its menu.
struct ClipboardFilterButton: View {
    let filter: ClipboardFilter
    let isOpen: Bool
    let action: () -> Void

    var body: some View {
        BarButton(chrome: .menu, action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: filter.systemImage)
                    .font(Theme.Typography.bar)
                    .symbolRenderingMode(.hierarchical)
                Text(filter.title)
                    .font(Theme.Typography.bar)
                    .lineLimit(1)
                // Points at the menu it opens, the way a native pop-up's chevron does.
                Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                    .font(Theme.Typography.disclosure)
            }
            .foregroundStyle(Theme.Colors.textSecondary)
        }
        .help("Filter by type  ⌘P")
    }
}
