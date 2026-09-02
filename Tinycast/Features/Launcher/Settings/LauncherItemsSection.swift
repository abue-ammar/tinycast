import SwiftUI

/// One category's Settings sections; never filters by visibility, so hidden rows stay listed.
struct LauncherItemsSection: View {
    let kind: AppEntry.Kind
    let anchor: SettingsAnchor
    let searchPrompt: String

    @Environment(AppIndex.self) private var appIndex
    @Environment(VisibilityStore.self) private var visibility
    @State private var query = ""

    private var entries: [AppEntry] {
        let scoped = appIndex.apps.filter { $0.kind == kind }
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

            if entries.isEmpty {
                Text(query.isEmpty ? "Nothing here yet." : "No matches for “\(query)”.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                // One row holding a lazy stack: a `Form` realizes every row it is handed.
                LazyVStack(spacing: 0) {
                    ForEach(entries) { entry in
                        if entry.id != entries.first?.id { Divider() }
                        LauncherItemRow(entry: entry)
                            .padding(.vertical, Self.rowPadding)
                    }
                }
                .padding(.vertical, -Self.rowPadding)
            }
        }
        .settingsEnabled(visibility.isKindEnabled(kind))
    }

    /// A grouped `Form` row's own vertical padding.
    private static let rowPadding: CGFloat = 15

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { visibility.isKindEnabled(kind) },
            set: { visibility.setKindEnabled($0, for: kind) }
        )
    }
}

private struct LauncherItemRow: View {
    let entry: AppEntry
    @Environment(VisibilityStore.self) private var visibility

    var body: some View {
        SettingsRow(title: entry.name) {
            AppIconView(app: entry).frame(width: 18, height: 18)
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
