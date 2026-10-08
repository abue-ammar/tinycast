import SwiftUI

/// The Raycast Store's search, and an install button per result.
struct ExtensionStorePanel: View {
    let storeInstall: ExtensionDeepLink.StoreInstall?
    let onClose: () -> Void
    @Environment(AppCore.self) private var core

    @State private var query = ""
    @State private var results: [ExtensionListing] = []
    @State private var searchFailure: String?
    @State private var searching = false
    @State private var searched = false
    @State private var installing: [String: ExtensionInstaller.Progress] = [:]
    @State private var failures: [String: String] = [:]
    @State private var installed: Set<String> = []
    @State private var searchTask: Task<Void, Never>?

    init(storeInstall: ExtensionDeepLink.StoreInstall? = nil, onClose: @escaping () -> Void) {
        self.storeInstall = storeInstall
        self.onClose = onClose
        _searching = State(initialValue: storeInstall != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            ExtensionSettingsEditorHeader(
                title: storeInstall == nil ? "Search Extensions" : "Install Extension",
                subtitle: "The Raycast Store's extensions arrive built, so they install as they are.")
            // The same borderless field the panes use, rather than a bordered capsule of its own.
            if storeInstall == nil {
                SettingsFilterField(prompt: "Search extensions…", query: $query)
            }
            content
            // The list scrolls right up to the footer without it, cutting the last row.
            Divider()
            footer
        }
        .padding(Theme.Spacing.dialogInset)
        .frame(width: 620, height: 560)
        .extensionSettingsEditorPanelSurface()
        .onChange(of: query) { _, value in scheduleSearch(value) }
        .onDisappear { searchTask?.cancel() }
        .task {
            if let storeInstall { await loadListings(query: storeInstall.name) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if storeInstall == nil && query.trimmingCharacters(in: .whitespaces).isEmpty {
            emptyState
        } else if searching && results.isEmpty {
            VStack(spacing: Theme.Spacing.md) {
                ProgressView()
                Text(storeInstall == nil ? "Searching…" : "Looking up extension…")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let searchFailure {
            placeholder(searchFailure)
        } else if results.isEmpty && searched {
            placeholder(
                storeInstall.map { "“\($0.handle)/\($0.name)” is unavailable in the Raycast Store." }
                    ?? "Nothing matches “\(query)”.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    ForEach(results) { listing in
                        StoreRow(
                            listing: listing,
                            state: state(for: listing),
                            onInstall: { install(listing) })
                    }
                }
                .hideNativeScrollers()
            }
            .overflowFade()
            .thinScrollbar()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Not a bare line of text in a tall empty panel: says what to do and what it will search.
    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Search for an extension")
                .font(.headline)
            Text(
                "By name, or by what it does — \u{201C}colour\u{201D}, \u{201C}github\u{201D}, \u{201C}window\u{201D}."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Spacer()
            // Escape, not Return: Return belongs to the search field while typing.
            Button("Done", action: onClose)
                .buttonStyle(
                    ExtensionSettingsEditorButtonStyle(role: .cancel, fillsWidth: false)
                )
                .keyboardShortcut(.cancelAction)
        }
    }

    // MARK: - State

    private func state(for listing: ExtensionListing) -> StoreRow.InstallState {
        if installed.contains(listing.name) { return .installed }
        if let progress = installing[listing.id] { return .installing(progress.message) }
        if let failure = failures[listing.id] { return .failed(failure) }
        if core.extensions.installed.contains(where: { $0.manifest.name == listing.name }) {
            return .alreadyInstalled
        }
        return .idle
    }

    // MARK: - Searching

    /// Debounced: every keystroke would otherwise be a request to someone else's API.
    private func scheduleSearch(_ value: String) {
        searchTask?.cancel()
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            searchFailure = nil
            searched = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await loadListings(query: trimmed)
        }
    }

    private func loadListings(query: String) async {
        searching = true
        defer {
            searching = false
            searched = true
        }
        do {
            let client = ExtensionStoreClient()
            let found: [ExtensionListing]
            if let storeInstall {
                found =
                    try await client.lookup(handle: storeInstall.handle, name: storeInstall.name)
                    .map { [$0] } ?? []
            } else {
                found = try await client.search(query)
            }
            guard !Task.isCancelled else { return }
            (results, searchFailure) = (found, nil)
        } catch {
            guard !Task.isCancelled else { return }
            (results, searchFailure) = ([], error.localizedDescription)
        }
    }

    // MARK: - Installing

    private func install(_ listing: ExtensionListing) {
        failures[listing.id] = nil
        installing[listing.id] = .downloading
        Task {
            do {
                try await core.extensions.install(
                    listing,
                    onProgress: { progress in
                        Task { @MainActor in installing[listing.id] = progress }
                    })
                installed.insert(listing.name)
            } catch {
                failures[listing.id] = error.localizedDescription
            }
            installing[listing.id] = nil
        }
    }
}

/// One search result: what it is, who made it, how many use it, and the button that installs it.
private struct StoreRow: View {
    enum InstallState: Equatable {
        case idle
        case installing(String)
        case installed
        case alreadyInstalled
        case failed(String)
    }

    /// Larger than a settings row's icon: in a store listing, the artwork is how a result is found.
    private static let iconSide: CGFloat = 40

    let listing: ExtensionListing
    let state: InstallState
    let onInstall: () -> Void
    @Environment(\.isDarkAppearance) private var isDark
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xl) {
            ExtensionIconView(
                resolved: listing.iconURL(isDark: isDark).map {
                    ExtensionImage.Resolved(source: .remote($0))
                },
                size: Self.iconSide)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(listing.title)
                    .font(.headline)
                    .lineLimit(1)
                if !listing.summary.isEmpty {
                    Text(listing.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                facts
                if case .failed(let message) = state {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.Spacing.md)
            action
        }
        .padding(Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(hovered ? Theme.Colors.rowHover : .clear)
        )
        .onHover { hovered = $0 }
    }

    private var facts: some View {
        HStack(spacing: Theme.Spacing.xl) {
            if !listing.author.isEmpty {
                StoreFact(symbol: "person.crop.circle", text: listing.author)
            }
            StoreFact(
                symbol: "square.grid.2x2",
                text: "\(listing.commandCount) command\(listing.commandCount == 1 ? "" : "s")")
            if let downloads = listing.downloadCount, downloads > 0 {
                StoreFact(symbol: "arrow.down.circle", text: ExtensionListing.abbreviate(downloads))
                    .help("\(downloads.formatted()) installs")
            }
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private var action: some View {
        switch state {
        case .idle:
            Button("Install", action: onInstall)
                .buttonStyle(ExtensionSettingsEditorButtonStyle(role: .primary, fillsWidth: false))
        case .installing(let message):
            HStack(spacing: Theme.Spacing.sm) {
                ProgressView().controlSize(.small)
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            .fixedSize()
        case .installed:
            Label("Installed", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        case .alreadyInstalled:
            Button("Reinstall", action: onInstall)
                .buttonStyle(ExtensionSettingsEditorButtonStyle(role: .standard, fillsWidth: false))
                .help("Already installed. Reinstalling replaces it with the store's copy.")
        case .failed:
            Button("Retry", action: onInstall)
                .buttonStyle(ExtensionSettingsEditorButtonStyle(role: .standard, fillsWidth: false))
        }
    }
}

/// One fact under a result, behind the glyph that says what kind of fact it is.
private struct StoreFact: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: symbol)
            Text(text)
        }
        .lineLimit(1)
    }
}
