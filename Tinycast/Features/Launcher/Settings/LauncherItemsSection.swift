import SwiftUI

/// One category's Settings sections; never filters by visibility, so hidden rows stay listed.
struct LauncherItemsSection: View {
    let kind: AppEntry.Kind
    let anchor: SettingsAnchor
    let searchPrompt: String

    @Environment(AppIndex.self) private var appIndex
    @Environment(VisibilityStore.self) private var visibility
    @Environment(AliasStore.self) private var aliases
    @Environment(HotKeyManager.self) private var hotKeys
    @State private var query = ""
    @State private var recorderFrame: CGRect?

    private var entries: [AppEntry] {
        let scoped = appIndex.apps.filter { $0.kind == kind && $0.settingsOwner == nil }
        guard !query.isEmpty else { return scoped }
        // Membership only: score order would move the row being edited out from under the caret.
        let matched = Set(appIndex.matches(query).map(\.id))
        return scoped.filter { matched.contains($0.id) }
    }

    var body: some View {
        Section {
            Toggle(isOn: enabledBinding) {
                SettingsRowTitle(anchor, "Enable \(anchor.title)")
                Text("Off hides them all and stops their shortcuts. Uncheck one below to hide just that one.")
            }
        } header: {
            SettingsSectionHeader(anchor)
        }

        Section {
            SettingsFilterField(prompt: searchPrompt, query: $query)

            let entries = entries
            if entries.isEmpty {
                Text(query.isEmpty ? "Nothing here yet." : "No matches for “\(query)”.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                // One row holding the table: a `Form` realizes every row it is handed.
                LauncherItemsTable(
                    entries: entries, isEnabled: visibility.isKindEnabled(kind),
                    visibility: visibility, aliases: aliases, hotKeys: hotKeys,
                    recorderFrame: $recorderFrame
                )
                .overlay(alignment: .topLeading) { recorderStandIn }
            }
        }
        .settingsEnabled(visibility.isKindEnabled(kind))
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

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { visibility.isKindEnabled(kind) },
            set: { visibility.setKindEnabled($0, for: kind) }
        )
    }
}

/// One launcher item's row; a table cell hosts it and hands it new entries as the list scrolls.
struct LauncherItemRow: View {
    let entry: AppEntry
    @Environment(VisibilityStore.self) private var visibility

    var body: some View {
        SettingsRow(title: entry.name) {
            // Keyed so a reused cell seeds the new entry's icon on its first frame.
            AppIconView(app: entry).frame(width: 18, height: 18).id(entry.iconKey)
        } trailing: {
            AliasField(entry: entry)
            if let action = entry.hotKeyAction {
                ShortcutRecorder(action: action)
            }
            Toggle("", isOn: itemBinding)
                .labelsHidden()
                .toggleStyle(.checkbox)
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
