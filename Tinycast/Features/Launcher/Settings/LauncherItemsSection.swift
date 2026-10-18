import SwiftUI

/// A category's master switch stays available while its list is disabled.
struct LauncherCategorySwitchSection: View {
    let kind: AppEntry.Kind
    let anchor: SettingsAnchor
    /// Spelled out by the caller, so it is the very string its search entry carries.
    let title: LocalizedStringResource

    @Environment(VisibilityStore.self) private var visibility

    var body: some View {
        Section {
            Toggle(
                isOn: Binding(
                    get: { visibility.isKindEnabled(kind) },
                    set: { visibility.setKindEnabled($0, for: kind) }
                )
            ) {
                SettingsFeatureToggleLabel(
                    anchor: anchor, title: title,
                    subtitle: "Disables the feature and its associated shortcuts.")
            }
        }
    }
}

/// One category's Settings list; never filters by visibility, so hidden rows stay listed.
struct LauncherItemsSection: View {
    let kind: AppEntry.Kind
    let anchor: SettingsAnchor
    let searchPrompt: LocalizedStringResource
    var emptyMessage: LocalizedStringResource = "Nothing here yet."

    @Environment(AppIndex.self) private var appIndex
    @Environment(VisibilityStore.self) private var visibility
    @State private var query = ""

    private var entries: [AppEntry] {
        let scoped = appIndex.apps.filter { $0.kind == kind && $0.settingsOwner == nil }
        guard !query.isEmpty else { return scoped }
        // Membership only: score order would move the row being edited out from under the caret.
        let matched = Set(appIndex.matches(query).map(\.id))
        return scoped.filter { matched.contains($0.id) }
    }

    var body: some View {
        Section {
            SettingsFilterField(prompt: searchPrompt, query: $query)
            LauncherItemsList(
                entries: entries, query: query, isEnabled: visibility.isKindEnabled(kind),
                emptyMessage: emptyMessage)
        } header: {
            SettingsSectionHeader(anchor)
        }
        .settingsEnabled(visibility.isKindEnabled(kind))
    }
}

struct LauncherItemsList: View {
    let entries: [AppEntry]
    let query: String
    let isEnabled: Bool
    var emptyMessage: LocalizedStringResource = "Nothing here yet."

    @Environment(VisibilityStore.self) private var visibility
    @Environment(AliasStore.self) private var aliases
    @Environment(HotKeyManager.self) private var hotKeys
    @State private var recorderFrame: CGRect?

    var body: some View {
        if entries.isEmpty {
            Text(query.isEmpty ? emptyMessage : "No matches for “\(query)”.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        } else if entries.first?.kind != .application && entries.first?.kind != .appleShortcut {
            ForEach(entries) { entry in LauncherItemRow(entry: entry) }
        } else {
            // One row holding the table: a `Form` realizes every row it is handed.
            LauncherItemsTable(
                entries: entries, isEnabled: isEnabled,
                visibility: visibility, aliases: aliases, hotKeys: hotKeys,
                recorderFrame: $recorderFrame
            )
            .overlay(alignment: .topLeading) { recorderStandIn }
        }
    }

    /// The open recorder's anchor can't leave its hosted row, so this republishes its bounds here.
    @ViewBuilder
    private var recorderStandIn: some View {
        if let recorderFrame {
            Color.clear
                .frame(width: recorderFrame.width, height: recorderFrame.height)
                .anchorPreference(key: ShortcutRecorderAnchorKey.self, value: .bounds) { $0 }
                .position(x: recorderFrame.midX, y: recorderFrame.midY)
                .allowsHitTesting(false)
        }
    }
}

/// One launcher item's row; a table cell hosts it and hands it new entries as the list scrolls.
struct LauncherItemRow: View {
    let entry: AppEntry
    @Environment(VisibilityStore.self) private var visibility

    var body: some View {
        SettingsRow(
            title: entry.name,
            labelOpacity: visibility.isItemVisible(entry) ? 1 : 0.45
        ) {
            // Keyed so a reused cell seeds the new entry's icon on its first frame.
            AppIconView(app: entry)
                .frame(width: SettingsListMetrics.iconSize, height: SettingsListMetrics.iconSize)
                .id(entry.iconKey)
        } trailing: {
            AliasField(entry: entry)
            if let action = entry.hotKeyAction {
                ShortcutRecorder(action: action)
            }
            Toggle("", isOn: itemBinding)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .launcherVisibilityHelp()
                .accessibilityLabel("Show \(entry.name) in launcher")
        }
    }

    private var itemBinding: Binding<Bool> {
        Binding(
            get: { visibility.isItemVisible(entry) },
            set: { visibility.setItemVisible($0, for: entry) }
        )
    }
}
