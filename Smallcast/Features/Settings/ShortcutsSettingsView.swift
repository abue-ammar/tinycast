import SwiftUI

/// Settings → Shortcuts: everything the launcher can open, one tab per category (Applications / System Settings / Commands), each row with a visibility checkbox and hotkey recorder; never applies the visibility filter itself, so hidden rows stay re-checkable here.
struct ShortcutsSettingsView: View {
    @EnvironmentObject private var appIndex: AppIndex
    @State private var tab: AppEntry.Kind = .application
    @State private var query = ""

    private var entries: [AppEntry] {
        // Run the matcher once per render, then scope the results to the active tab.
        let matched = query.isEmpty ? appIndex.apps : appIndex.matches(query)
        return matched.filter { $0.kind == tab }
    }

    var body: some View {
        // Same insets as `SettingsPane`: ignore the transparent-titlebar safe area and use one fixed `xxl` inset every side.
        VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
            SettingsHeader(
                title: "Shortcuts",
                subtitle: "Choose what appears in the launcher and assign global shortcuts."
            )

            Picker("Category", selection: $tab) {
                Text("Applications").tag(AppEntry.Kind.application)
                Text("System Settings").tag(AppEntry.Kind.systemSettings)
                Text("Commands").tag(AppEntry.Kind.command)
            Text("Extensions").tag(AppEntry.Kind.extensionCommand)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            searchField

            CategoryCard(kind: tab, entries: entries, query: query)
        }
        .padding(Theme.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea(edges: .top)
    }

    private var searchPrompt: String {
        switch tab {
        case .application: return "Search applications…"
        case .systemSettings: return "Search System Settings…"
        case .command: return "Search commands…"
        case .extensionCommand: return "Search extension commands…"
        }
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(searchPrompt, text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.body)
        .padding(Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(Theme.Colors.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
        )
    }
}

/// The active tab's card: a header row with the "show in launcher" switch, then the item rows; rows dim when the category is off but stay interactive.
private struct CategoryCard: View {
    let kind: AppEntry.Kind
    let entries: [AppEntry]
    let query: String
    @EnvironmentObject private var visibility: VisibilityStore

    var body: some View {
        let kindVisible = visibility.isKindVisible(kind)
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Show in launcher")
                    .font(Theme.Typography.sectionHeader)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("", isOn: kindBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(.horizontal, Theme.Spacing.xs)

            // Plain windowed settings list; force the thin, auto-hiding overlay scroller so a system-wide "always show scroll bars" setting can't draw a wide legacy one.
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(entries) { entry in
                        ShortcutRow(entry: entry)
                    }
                }
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.sm)
                .overlayScroller()
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Colors.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
            )
            .overlay {
                if entries.isEmpty {
                    Text(query.isEmpty ? "Nothing here yet." : "No matches for “\(query)”.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .opacity(kindVisible ? 1 : 0.45)
        }
    }

    private var kindBinding: Binding<Bool> {
        Binding(
            get: { visibility.isKindVisible(kind) },
            set: { visibility.setKindVisible($0, for: kind) }
        )
    }
}

private struct ShortcutRow: View {
    let entry: AppEntry
    @EnvironmentObject private var visibility: VisibilityStore
    // Hover lives on the row itself so a mouse sweep repaints only the rows entering/leaving.
    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(nsImage: entry.icon)
                .resizable()
                .frame(width: 22, height: 22)
            Text(entry.name).lineLimit(1)
            Spacer(minLength: Theme.Spacing.xl)
            if let action = entry.hotKeyAction {
                ShortcutRecorder(action: action)
            }
            Toggle("", isOn: itemBinding)
                .labelsHidden()
                .toggleStyle(.checkbox)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(hovered ? Theme.Colors.rowHover : .clear)
        )
        .onHover { hovered = $0 }
    }

    private var itemBinding: Binding<Bool> {
        Binding(
            get: { visibility.isItemVisible(entry) },
            set: { visibility.setItemVisible($0, for: entry) }
        )
    }
}
