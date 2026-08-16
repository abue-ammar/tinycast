import SwiftUI

/// Search every configured registry and install from any of them, through one list.
///
/// Where a result comes from changes only two things a person can see: the badge on its row, and
/// whether installing it has to build first. Everything else is deliberately identical.
struct ExtensionStoreSheet: View {
    let onClose: () -> Void
    @Environment(AppCore.self) private var core

    @State private var query = ""
    @State private var results: [ExtensionListing] = []
    @State private var notices: [String] = []
    @State private var searching = false
    @State private var searched = false
    @State private var installing: [String: ExtensionInstaller.Progress] = [:]
    @State private var failures: [String: String] = [:]
    @State private var installed: Set<String> = []
    @State private var searchTask: Task<Void, Never>?
    @State private var editingRegistries = false

    private var registries: [ExtensionRegistry] { core.settings.extensionRegistries }

    /// Which registries this will actually cover, by name — the sheet can't reach the pane's registry
    /// settings, so at least it says what they are.
    private var searchingSummary: String {
        let on = registries.filter(\.isEnabled)
        guard !on.isEmpty else {
            return "No registries are enabled. Turn one on under Install → Where to search."
        }
        let names = on.map(\.name).joined(separator: ", ")
        return "Searching \(names). Store extensions install as they are; a repository is built first."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            header
            // The same borderless field the panes use, rather than a bordered capsule of its own.
            SettingsFilterField(prompt: "Search extensions…", query: $query)
            content
            // The list scrolls right up to the footer without it, cutting the last row mid-sentence.
            Divider()
            footer
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: 620, height: 560)
        .onChange(of: query) { _, value in scheduleSearch(value) }
        // Re-run against whatever the registries now are, so the results match the header again.
        .onChange(of: core.settings.extensionRegistries) { _, _ in scheduleSearch(query) }
        .sheet(isPresented: $editingRegistries) {
            ExtensionRegistriesSheet(onClose: { editingRegistries = false })
        }
        .onDisappear { searchTask?.cancel() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            // Named for the row that opens it, and it names the registries rather than counting them.
            HStack(alignment: .firstTextBaseline) {
                Text("Search Extensions").font(.title2.weight(.bold))
                Spacer()
                // Changing what is searched belongs in the flow, not back out in the pane.
                Button("Registries…") { editingRegistries = true }
            }
            Text(searchingSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if registries.filter(\.isEnabled).isEmpty {
            // Otherwise this is a search field that can only ever find nothing.
            noRegistriesState
        } else if query.trimmingCharacters(in: .whitespaces).isEmpty {
            emptyState
        } else if searching && results.isEmpty {
            VStack(spacing: Theme.Spacing.md) {
                ProgressView()
                Text("Searching…").font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty && searched {
            placeholder("Nothing matches “\(query)”.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(results) { listing in
                        StoreRow(
                            listing: listing,
                            state: state(for: listing),
                            onInstall: { install(listing) })
                        Divider().opacity(0.4)
                    }
                }
                .hideNativeScrollers()
            }
            .overflowFade()
            .thinScrollbar()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Not a bare line of text in a tall empty sheet: says what to do and what it will search.
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

    /// Nothing is searchable, so the only useful thing here is the way to fix that.
    private var noRegistriesState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "tray")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No registries enabled")
                .font(.headline)
            Text("Turn one on and this will have somewhere to look.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Registries…") { editingRegistries = true }
                .padding(.top, Theme.Spacing.xs)
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
        HStack(alignment: .firstTextBaseline) {
            // A registry that failed is worth saying so about — the results are quietly incomplete.
            if !notices.isEmpty {
                Label(notices.joined(separator: " · "), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
            Spacer()
            Button("Done", action: onClose)
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - State

    private func state(for listing: ExtensionListing) -> StoreRow.State {
        if installed.contains(listing.name) { return .installed }
        if let progress = installing[listing.id] { return .installing(progress.message) }
        if let failure = failures[listing.id] { return .failed(failure) }
        if core.extensions.installed.contains(where: { $0.manifest.name == listing.name }) {
            return .alreadyInstalled
        }
        return .idle
    }

    // MARK: - Searching

    /// Debounced, because every keystroke is a request to someone else's API — and, for a GitHub
    /// registry, a handful of manifest reads against an anonymous rate limit of sixty an hour.
    private func scheduleSearch(_ value: String) {
        searchTask?.cancel()
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            notices = []
            searched = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await search(trimmed)
        }
    }

    private func search(_ trimmed: String) async {
        searching = true
        defer {
            searching = false
            searched = true
        }
        let found = await ExtensionStoreClient().search(trimmed, in: registries)
        guard !Task.isCancelled else { return }

        // The store's copy wins a tie: it is prebuilt, so installing it needs no toolchain.
        var seen = Set<String>()
        var merged: [ExtensionListing] = []
        for result in found {
            for listing in result.listings where seen.insert(listing.name).inserted {
                merged.append(listing)
            }
        }
        results = merged
        notices = found.compactMap { result in
            result.failure.map { "\(result.registry.name): \($0)" }
        }
    }

    // MARK: - Installing

    private func install(_ listing: ExtensionListing) {
        failures[listing.id] = nil
        installing[listing.id] = .downloading
        Task {
            do {
                try await core.extensions.install(
                    listing: listing,
                    packageManager: core.settings.extensionPackageManager,
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

/// One search result: what it is, where it came from, and the button that installs it.
private struct StoreRow: View {
    enum State: Equatable {
        case idle
        case installing(String)
        case installed
        case alreadyInstalled
        case failed(String)
    }

    let listing: ExtensionListing
    let state: State
    let onInstall: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.lg) {
            ExtensionIconView(
                resolved: listing.iconURL.map { ExtensionImage.Resolved(source: .remote($0)) },
                size: 32)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(listing.title).font(.body.weight(.medium))
                    if listing.needsBuild {
                        Text("builds on install")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.Colors.controlSurface, in: .capsule)
                            .foregroundStyle(.secondary)
                            .help(
                                "This registry serves source. Installing runs your package manager "
                                    + "and the extension's build script.")
                    }
                }
                if !listing.summary.isEmpty {
                    Text(listing.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(listing.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if case .failed(let message) = state {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.Spacing.md)
            action
        }
        .padding(.vertical, Theme.Spacing.md)
    }

    @ViewBuilder
    private var action: some View {
        switch state {
        case .idle:
            Button("Install", action: onInstall)
        case .installing(let message):
            HStack(spacing: Theme.Spacing.sm) {
                ProgressView().controlSize(.small)
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            .fixedSize()
        case .installed:
            Label("Installed", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)
        case .alreadyInstalled:
            Button("Reinstall", action: onInstall)
                .help("Already installed. Reinstalling replaces it with the registry's copy.")
        case .failed:
            Button("Retry", action: onInstall)
        }
    }
}
