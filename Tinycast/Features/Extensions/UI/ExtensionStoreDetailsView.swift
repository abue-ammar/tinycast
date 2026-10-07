import SwiftUI

struct ExtensionStoreDetailsView: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.isDarkAppearance) private var isDark
    @FocusState private var focused: Bool
    let listing: ExtensionListing
    let onOpenURL: (URL) -> Void

    private enum Layout {
        static let icon: CGFloat = 52
        static let titleSize: CGFloat = 26
        static let sidebar: CGFloat = 180
        static let screenshotWidth: CGFloat = 340
        static let screenshotHeight: CGFloat = 210
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.spacing.xxl) {
                heading
                if !listing.screenshots.isEmpty {
                    screenshots
                }
                HStack(alignment: .top, spacing: metrics.spacing.xxl) {
                    descriptionAndCommands
                        .frame(maxWidth: .infinity, alignment: .leading)
                    sidebar
                        .frame(width: metrics.scaled(Layout.sidebar), alignment: .leading)
                }
            }
            .padding(metrics.spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hideNativeScrollers()
        }
        .edgeDissolve()
        .thinScrollbar()
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .defaultFocus($focused, true)
        .task {
            await Task.yield()
            focused = true
        }
    }

    private var heading: some View {
        HStack(spacing: metrics.spacing.xl) {
            ExtensionIconView(
                resolved: listing.iconURL(isDark: isDark).map {
                    ExtensionImage.Resolved(source: $0.isFileURL ? .file($0.path) : .remote($0))
                },
                size: metrics.scaled(Layout.icon))
            VStack(alignment: .leading, spacing: metrics.spacing.sm) {
                Text(listing.title)
                    .font(.system(size: metrics.scaled(Layout.titleSize), weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                HStack(spacing: metrics.spacing.md) {
                    Text(listing.author)
                    if let count = listing.downloadCount {
                        SymbolImage(name: "arrow.down.circle", size: metrics.size.menuIcon)
                        Text(ExtensionListing.abbreviate(count))
                            .accessibilityLabel("\(count) installs")
                    }
                }
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    private var screenshots: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: metrics.spacing.xl) {
                ForEach(listing.screenshots, id: \.absoluteString) { url in
                    Button {
                        onOpenURL(url)
                    } label: {
                        Screenshot(url: url)
                            .frame(
                                width: metrics.scaled(Layout.screenshotWidth),
                                height: metrics.scaled(Layout.screenshotHeight))
                            .background(Theme.Colors.cardFill)
                            .clipShape(
                                RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(listing.title) screenshot")
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var descriptionAndCommands: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.xxl) {
            Text("Description")
                .font(metrics.typography.panelTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(listing.summary)
                .font(metrics.typography.rowTitle)
                .foregroundStyle(Theme.Colors.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: metrics.spacing.xl) {
                Text("Commands")
                    .font(metrics.typography.panelTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if listing.commands.isEmpty {
                    Text("\(listing.commandCount) commands")
                        .font(metrics.typography.rowTitle)
                        .foregroundStyle(Theme.Colors.textSecondary)
                } else {
                    ForEach(listing.commands, id: \.name) { command in
                        VStack(alignment: .leading, spacing: metrics.spacing.xs) {
                            HStack(spacing: metrics.spacing.md) {
                                SymbolImage(
                                    name: command.mode == "no-view" ? "bolt" : "terminal",
                                    size: metrics.size.menuIcon)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                Text(command.title)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                            }
                            .font(metrics.typography.rowTitle)
                            if !command.summary.isEmpty {
                                Text(command.summary)
                                    .font(metrics.typography.rowTrailing)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.xxl) {
            if let url = listing.readmeURL {
                Button {
                    onOpenURL(url)
                } label: {
                    HStack(spacing: metrics.spacing.md) {
                        SymbolImage(name: "doc.text", size: metrics.size.menuIcon)
                        Text("Open README")
                        Spacer(minLength: 0)
                        SymbolImage(name: "arrow.up.right", size: metrics.size.menuIcon)
                    }
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(metrics.spacing.md)
                    .background(
                        Theme.Colors.controlSurface,
                        in: RoundedRectangle(cornerRadius: metrics.radius.menu, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            if let updatedAt = listing.updatedAt {
                VStack(alignment: .leading, spacing: metrics.spacing.sm) {
                    sidebarHeading("Last Update")
                    Text(updatedAt, style: .relative)
                        .font(metrics.typography.rowTrailing)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
            }
            if !listing.contributors.isEmpty {
                VStack(alignment: .leading, spacing: metrics.spacing.md) {
                    sidebarHeading("Contributors")
                    ForEach(listing.contributors, id: \.handle) { contributor in
                        HStack(spacing: metrics.spacing.sm) {
                            ExtensionIconView(
                                resolved: contributor.avatarURL.map {
                                    ExtensionImage.Resolved(source: .remote($0), isCircular: true)
                                },
                                size: metrics.size.rowIcon)
                            Text(contributor.name)
                                .font(metrics.typography.rowTrailing)
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                    }
                }
            }
            if !listing.categories.isEmpty {
                VStack(alignment: .leading, spacing: metrics.spacing.md) {
                    sidebarHeading("Categories")
                    ForEach(listing.categories, id: \.self) { category in
                        Text(category)
                            .font(metrics.typography.rowTrailing)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .padding(.horizontal, metrics.spacing.md)
                            .padding(.vertical, metrics.spacing.xs)
                            .background(
                                Theme.Colors.controlSurface,
                                in: RoundedRectangle(cornerRadius: metrics.radius.menu, style: .continuous))
                    }
                }
            }
        }
    }

    private func sidebarHeading(_ text: String) -> some View {
        Text(text)
            .font(metrics.typography.sectionHeader)
            .foregroundStyle(Theme.Colors.textSecondary)
    }

    private struct Screenshot: View {
        @Environment(\.isDarkAppearance) private var isDark
        let url: URL
        @State private var loaded: NSImage?

        var body: some View {
            Group {
                if let loaded {
                    Image(nsImage: loaded)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: ExtensionImage.LoadKey(source: .remote(url), isDark: isDark)) {
                let image = await ExtensionImage.load(
                    ExtensionImage.Resolved(source: .remote(url)), isDark: isDark, animates: true)
                if !Task.isCancelled { loaded = image }
            }
            .onDisappear { loaded = nil }
        }
    }
}
