import SwiftUI

struct ExtensionStoreFooter: View {
    let listing: ExtensionListing?
    let onMenu: () -> Void
    @Environment(\.metrics) private var metrics
    @Environment(\.isDarkAppearance) private var isDark

    var body: some View {
        Button(action: onMenu) {
            HStack(spacing: metrics.spacing.md) {
                if let listing {
                    ExtensionIconView(
                        resolved: listing.iconURL(isDark: isDark).map {
                            ExtensionImage.Resolved(source: $0.isFileURL ? .file($0.path) : .remote($0))
                        }, size: metrics.size.rowIcon)
                } else {
                    SymbolImage(name: "bag", size: metrics.size.rowIcon)
                }
                Text(listing?.title ?? "Store")
                    .font(metrics.typography.bar)
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.Colors.textSecondary)
            .padding(.horizontal, metrics.spacing.xl)
            .frame(height: metrics.size.menuButton)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frosted(in: Capsule())
        .tooltip("Store menu")
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
