import SwiftUI
import UniformTypeIdentifiers

struct ClipboardSettingsView: View {
    @ObservedObject private var settings = AppCore.shared.settings
    @State private var confirmingClear = false
    @State private var showingAppPicker = false

    var body: some View {
        SettingsPane(
            title: "Clipboard",
            subtitle: "Control how much history Smallcast keeps and which apps are recorded."
        ) {
            SettingsCard(header: "Shortcut") {
                SettingsRow(
                    title: "Clipboard History",
                    subtitle: "Open the clipboard history browser.",
                    systemImage: "doc.on.clipboard",
                    tint: .orange
                ) {
                    ShortcutRecorder(action: .toggleClipboard)
                }
            }

            SettingsCard(header: "History") {
                SettingsRow(
                    title: "Keep history for",
                    subtitle: "Entries older than this are deleted automatically.",
                    systemImage: "clock.arrow.circlepath",
                    tint: .orange
                ) {
                    Picker("", selection: $settings.clipboardRetention) {
                        ForEach(ClipboardRetention.allCases) { retention in
                            Text(retention.title).tag(retention)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: settings.clipboardRetention) {
                        let store = AppCore.shared.clipboardStore
                        store.maxAge = settings.clipboardRetention.maxAge
                        store.enforceLimits()
                    }
                }
            }

            SettingsCard(header: "Disabled Applications") {
                ForEach(settings.clipboardDisabledApps, id: \.self) { bundleID in
                    DisabledAppRow(bundleID: bundleID) {
                        settings.clipboardDisabledApps.removeAll { $0 == bundleID }
                    }
                    SettingsDivider()
                }

                HStack(spacing: Theme.Spacing.lg) {
                    Text("Clipboard changes from these apps won't be recorded.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: Theme.Spacing.xl)
                    Button {
                        showingAppPicker = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $showingAppPicker, arrowEdge: .bottom) {
                        AppPickerPopover(excluded: Set(settings.clipboardDisabledApps)) { bundleID in
                            settings.clipboardDisabledApps.append(bundleID)
                            showingAppPicker = false
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.md)
            }

            SettingsCard(header: "Danger Zone") {
                SettingsRow(
                    title: "Clear history",
                    subtitle: "Permanently remove every saved clip and image.",
                    systemImage: "trash",
                    tint: .red
                ) {
                    Button("Clear…", role: .destructive) { confirmingClear = true }
                        .controlSize(.regular)
                }
            }
        }
        .confirmationDialog(
            "Clear clipboard history?",
            isPresented: $confirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                AppCore.shared.clipboardStore.clearAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }
}

/// One excluded app (icon + name + remove button); the stored value is just a bundle ID, so name/icon resolve on the fly via the app index, else LaunchServices, else a placeholder for uninstalled apps.
private struct DisabledAppRow: View {
    let bundleID: String
    let onRemove: () -> Void

    @EnvironmentObject private var appIndex: AppIndex

    var body: some View {
        let (name, icon) = resolve()
        HStack(spacing: Theme.Spacing.lg) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 22, height: 22)
            Text(name)
                .font(.body)
                .lineLimit(1)
            Spacer(minLength: Theme.Spacing.xl)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
    }

    private func resolve() -> (String, NSImage) {
        if let app = appIndex.apps.first(where: { $0.bundleID == bundleID }) {
            return (app.name, app.icon)
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = url.deletingPathExtension().lastPathComponent
            return (name, IconCache.icon(forFile: url.path))
        }
        return (bundleID, NSWorkspace.shared.icon(for: .applicationBundle))
    }
}

/// Searchable list of installed apps (from the launcher's index) used to add a disabled app.
private struct AppPickerPopover: View {
    let excluded: Set<String>
    let onSelect: (String) -> Void

    @EnvironmentObject private var appIndex: AppIndex
    @State private var query = ""

    private var candidates: [AppEntry] {
        (query.isEmpty ? appIndex.apps : appIndex.matches(query))
            .filter { $0.kind == .application }
            .filter { $0.bundleID.map { !excluded.contains($0) } ?? false }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search apps…", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(Theme.Spacing.md)
            Divider()
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(candidates) { app in
                        Button {
                            if let id = app.bundleID { onSelect(id) }
                        } label: {
                            HStack(spacing: Theme.Spacing.lg) {
                                Image(nsImage: app.icon)
                                    .resizable()
                                    .frame(width: 20, height: 20)
                                Text(app.name)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Theme.Spacing.sm)
            }
        }
        .frame(width: 280, height: 320)
    }
}
