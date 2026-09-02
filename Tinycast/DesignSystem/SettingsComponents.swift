import SwiftUI

// The few pieces more than one Settings pane needs; everything else is a stock `Form` section.

/// Not `LabeledContent`: its selectable text field eats the taps a `ShortcutRecorder` needs.
struct SettingsRow<Icon: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    /// Set when a search result points at this row, so its title can carry the pulse.
    var anchor: SettingsAnchor?
    @ViewBuilder var icon: Icon
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            icon
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Group {
                    if let anchor {
                        SettingsRowTitle(anchor, title)
                    } else {
                        Text(title)
                    }
                }
                .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(subtitle)
                }
            }
            Spacer(minLength: Theme.Spacing.lg)
            trailing
        }
    }
}

extension SettingsRow where Icon == EmptyView {
    init(
        title: String, subtitle: String? = nil, anchor: SettingsAnchor? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(
            title: title, subtitle: subtitle, anchor: anchor, icon: { EmptyView() },
            trailing: trailing)
    }
}

extension View {
    /// Dims as well as disables; `.disabled` alone leaves the title at full strength.
    func settingsEnabled(_ isEnabled: Bool) -> some View {
        disabled(!isEnabled).opacity(isEnabled ? 1 : 0.45)
    }
}

/// A feature pane's opening section: the master switch, then its launcher-visibility companion.
struct FeatureSwitchSection: View {
    let anchor: SettingsAnchor
    let enableTitle: String
    let enableSubtitle: String
    let launcherSubtitle: String
    @Binding var isEnabled: Bool
    @Binding var showsInLauncher: Bool

    var body: some View {
        Section {
            Toggle(isOn: $isEnabled) {
                SettingsRowTitle(anchor, enableTitle)
                Text(enableSubtitle)
            }
            Toggle(isOn: $showsInLauncher) {
                Text("Show in launcher")
                Text(launcherSubtitle)
            }
            // The switch above stays live so the feature can always be turned back on.
            .settingsEnabled(isEnabled)
        } header: {
            SettingsSectionHeader(anchor)
        }
    }
}

/// The filter row above a long list, shaped like a search field rather than a form text field.
struct SettingsFilterField: View {
    let prompt: String
    @Binding var query: String
    /// The plain field has no bezel: without this only the glyphs are a target.
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            // `prompt:` + `labelsHidden`, or the form makes the placeholder a left-column heading.
            TextField("", text: $query, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .labelsHidden()
                .focused($focused)
                .pointerStyle(.horizontalText)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .contentShape(.rect)
        .onTapGesture { focused = true }
    }
}

/// Dressed like `ShortcutRecorder`; a persistent `TextField` — swapping views broke repeat focus.
struct AliasField: View {
    /// The owner's `preferenceKey`, taken raw so a row without an `AppEntry` can carry one too.
    let key: String
    let name: String
    @Environment(AliasStore.self) private var aliases
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
        let placeholder = Text("Add Alias").foregroundStyle(Theme.Colors.textSecondary)
        HStack(spacing: Theme.Spacing.xs) {
            TextField("", text: $draft, prompt: placeholder)
                .textFieldStyle(.plain)
                .labelsHidden()
                .font(Theme.Typography.keyCap)
                .focused($focused)
                // The system ring insets the field editor on focus, hopping the placeholder left.
                .focusEffectDisabled()
                .onSubmit(commit)
                .onExitCommand(perform: revert)
                // The pane's `releasesFocusOnOutsideClick` resigns; this catches it landing.
                .onChange(of: focused) { _, now in
                    if !now { commit() }
                }
            if !draft.isEmpty {
                Button(action: clear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear alias for \(name)")
            }
        }
        .onAppear { draft = aliases.alias(for: key) ?? "" }
        // A backup import replaces the table out from under an unfocused row.
        .onChange(of: aliases.revision) { _, _ in
            if !focused { draft = aliases.alias(for: key) ?? "" }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .frame(width: Theme.Size.shortcutRecorder, height: 24)
        .background(shape.fill(Theme.Colors.cardFill))
        .overlay(
            shape.strokeBorder(
                focused ? Color.accentColor : Theme.Colors.cardStroke, lineWidth: 1)
        )
        .clipShape(shape)
        .accessibilityLabel("Alias for \(name)")
    }

    /// The one commit path — ↵ or focus landing elsewhere; a blank draft removes the alias.
    private func commit() {
        aliases.setAlias(draft, for: key)
        draft = aliases.alias(for: key) ?? ""
    }

    private func revert() {
        draft = aliases.alias(for: key) ?? ""
        focused = false
    }

    private func clear() {
        draft = ""
        commit()
    }
}

extension AliasField {
    init(entry: AppEntry) {
        self.init(key: entry.preferenceKey, name: entry.name)
    }
}
