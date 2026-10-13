import SwiftUI

/// Builds one extension from its GitHub source; only the build is kept.
struct ExtensionGitHubPanel: View {
    let onClose: () -> Void

    @Environment(AppCore.self) private var core
    @State private var repository = ""
    @State private var progress: ExtensionInstaller.Progress?
    @State private var failure: String?
    @State private var installedTitle: String?
    @State private var installTask: Task<Void, Never>?

    private var source: ExtensionGitHubSource? { ExtensionGitHubSource(repository) }
    private var isInstalling: Bool { progress != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            ExtensionSettingsEditorHeader(
                title: "Install from GitHub",
                subtitle: "Builds an extension from source on this Mac. Only the build is kept — "
                    + "the source and its dependencies are deleted once it installs.")

            repositoryField
            ExtensionToolchainFields()
                .disabled(isInstalling)

            Text(
                "Installing runs your package manager and the extension's own build script. "
                    + "Install only from someone you trust."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            status

            HStack(spacing: Theme.Spacing.md) {
                Button(installedTitle == nil ? "Cancel" : "Done", action: onClose)
                    .buttonStyle(ExtensionSettingsEditorButtonStyle(role: .cancel))
                    .keyboardShortcut(.cancelAction)
                Button("Install", action: install)
                    .buttonStyle(ExtensionSettingsEditorButtonStyle(role: .primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(source == nil || isInstalling)
            }
        }
        .padding(Theme.Spacing.dialogInset)
        .frame(width: Theme.Size.editorSheetWidth)
        .extensionSettingsEditorPanelSurface()
        .onChange(of: repository) {
            failure = nil
            installedTitle = nil
        }
        // Closing mid-build stops it; the workspace goes with it, so nothing half-built remains.
        .onDisappear { installTask?.cancel() }
    }

    private var repositoryField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Repository").font(.callout.weight(.medium))
            TextField("", text: $repository, prompt: Text("owner/repo, or a link to the extension's folder"))
                .extensionSettingsEditorTextField()
                .pointerStyle(.horizontalText)
                .disabled(isInstalling)
            if let source {
                Text("Builds \(source.summary).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !repository.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("That doesn't look like a GitHub repository.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if let progress {
            HStack(spacing: Theme.Spacing.sm) {
                ProgressView().controlSize(.small)
                Text(progress.message).font(.caption).foregroundStyle(.secondary)
            }
        } else if let failure {
            Label(failure, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else if let installedTitle {
            Label("Installed \(installedTitle).", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        }
    }

    private func install() {
        guard let source, !isInstalling else { return }
        let settings = core.settings
        failure = nil
        installedTitle = nil
        progress = .downloading
        installTask = Task {
            defer { progress = nil }
            do {
                let installed = try await core.extensions.install(
                    source, packageManager: settings.extensionPackageManager,
                    additionalSearchPaths: settings.extensionCustomSearchPaths,
                    onProgress: { step in
                        // Guarded: a late hop must not revive the spinner after the install ends.
                        Task { @MainActor in if progress != nil { progress = step } }
                    })
                installedTitle = installed.title
            } catch {
                guard !Task.isCancelled else { return }
                failure = error.localizedDescription
            }
        }
    }
}

/// Its own view, so typing a repository doesn't probe the disk for package managers per key.
private struct ExtensionToolchainFields: View {
    @Environment(AppCore.self) private var core
    /// Written back only on a real edit, so a round trip cannot strip the separator.
    @State private var searchPathsText = ""

    var body: some View {
        @Bindable var settings = core.settings
        return VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Text("Package manager").font(.callout.weight(.medium))
                    Spacer()
                    Picker("", selection: $settings.extensionPackageManager) {
                        ForEach(ExtensionPackageManager.allCases) { manager in
                            Text(manager.title).tag(manager)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Text(packageManagerDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Custom search paths").font(.callout.weight(.medium))
                TextField("", text: $searchPathsText, prompt: Text("~/.local/share/mise/shims"))
                    .extensionSettingsEditorTextField()
                    .pointerStyle(.horizontalText)
                    .onChange(of: searchPathsText) { _, value in
                        settings.extensionCustomSearchPaths = Self.parseSearchPaths(value)
                    }
                Text(
                    "Colon-separated, like PATH — checked before Homebrew and the rest. For mise: "
                        + "~/.local/share/mise/shims. For Nix (Home Manager): "
                        + "/etc/profiles/per-user/<you>/home-path/bin."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            searchPathsText = core.settings.extensionCustomSearchPaths.joined(separator: ":")
        }
    }

    private var packageManagerDetail: String {
        let chosen = core.settings.extensionPackageManager
        let additionalSearchPaths = core.settings.extensionCustomSearchPaths
        guard let resolved = chosen.resolve(additionalSearchPaths: additionalSearchPaths) else {
            return chosen == .automatic
                ? "None found on this Mac. Install pnpm, npm, Yarn or Bun to build an extension."
                : "\(chosen.title) isn't installed on this Mac."
        }
        return chosen == .automatic
            ? "Found \(resolved.manager.title) at \(resolved.url.path)."
            : "Found at \(resolved.url.path)."
    }

    private static func parseSearchPaths(_ text: String) -> [String] {
        text.split(separator: ":", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
