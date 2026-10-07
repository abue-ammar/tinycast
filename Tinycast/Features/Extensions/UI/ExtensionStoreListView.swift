import SwiftUI

struct ExtensionStoreListView: View {
    let listings: [ExtensionListing]
    let session: ExtensionStoreSession
    let coordinator: ExtensionStoreCoordinator
    let selection: Int
    let scroll: ScrollIntent
    let onSelect: (Int) -> Void
    let onActivate: (Int) -> Void
    let onActions: (Int) -> Void
    @Environment(\.metrics) private var metrics

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    SectionHeader(
                        title: session.installedOnly ? "Installed Extensions" : session.category ?? "All Extensions",
                        isFirst: true)
                    ForEach(Array(listings.enumerated()), id: \.element.id) { index, listing in
                        ExtensionStoreListingRow(
                            listing: listing, selected: index == selection,
                            installed: coordinator.isInstalled(listing))
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(index); onActivate(index) }
                        .onRightClick { onActions(index) }
                        .selectionFrame(index == selection)
                        .id(listing.id)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { onActivate(index) }
                        .onAppear {
                            if index >= listings.count - 3 { session.loadMore() }
                        }
                    }
                    status
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.top, metrics.spacing.xl)
                .padding(.bottom, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll, row: listings.indices.contains(selection) ? listings[selection].id : nil,
                atOrigin: selection == 0, proxy: proxy)
        }
    }

    @ViewBuilder
    private var status: some View {
        if session.isLoading {
            ProgressView().controlSize(.small).padding(metrics.spacing.xl)
        } else if let failure = session.failure {
            VStack(spacing: metrics.spacing.md) {
                Text(failure).foregroundStyle(Theme.Colors.textSecondary)
                Button("Retry") {
                    if listings.isEmpty { coordinator.retry() } else { session.loadMore() }
                }
            }
            .font(metrics.typography.rowTrailing)
            .padding(metrics.spacing.xxl)
        } else if session.hasMore {
            Button("Load More") { session.loadMore() }
                .onAppear { if listings.isEmpty { session.loadMore() } }
                .padding(metrics.spacing.xl)
        } else if listings.isEmpty {
            EmptyResults(text: session.installedOnly ? "No installed extensions match" : "No extensions found")
        }
    }
}

private struct ExtensionStoreListingRow: View {
    let listing: ExtensionListing
    let selected: Bool
    let installed: Bool
    @Environment(\.metrics) private var metrics
    @Environment(\.isDarkAppearance) private var isDark
    @State private var hovered = false

    private static let iconSide: CGFloat = 32
    private static let avatarSide: CGFloat = 16
    private static let rowHeight: CGFloat = 58

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            ExtensionIconView(
                resolved: listing.iconURL(isDark: isDark).map {
                    ExtensionImage.Resolved(source: $0.isFileURL ? .file($0.path) : .remote($0))
                },
                size: metrics.scaled(Self.iconSide))
            VStack(alignment: .leading, spacing: metrics.spacing.xs) {
                Text(listing.title).font(metrics.typography.rowTitle).lineLimit(1)
                Text(listing.summary)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: metrics.spacing.md)
            if installed {
                SymbolImage(name: "checkmark.circle", size: metrics.size.menuIcon)
                    .foregroundStyle(Theme.Colors.success)
                    .accessibilityLabel("Installed")
            }
            if let count = listing.downloadCount {
                HStack(spacing: metrics.spacing.xs) {
                    SymbolImage(name: "arrow.down.circle", size: metrics.size.menuIcon)
                    Text(ExtensionListing.abbreviate(count))
                }
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textTertiary)
            }
            if let avatar = listing.authorAvatarURL {
                ExtensionIconView(
                    resolved: ExtensionImage.Resolved(source: .remote(avatar)),
                    size: metrics.scaled(Self.avatarSide))
                    .clipShape(Circle())
            }
        }
        .padding(metrics.spacing.md)
        .frame(minHeight: metrics.scaled(Self.rowHeight))
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(selected ? Theme.Colors.selection : hovered ? Theme.Colors.rowHover : .clear))
        .onHover { hovered = $0 }
        .accessibilityElement(children: .combine)
    }
}
