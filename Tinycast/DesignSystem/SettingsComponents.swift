import SwiftUI

// The few pieces more than one Settings pane needs; everything else is a stock `Form` section.

/// Not `LabeledContent`: its selectable text field eats the taps a `ShortcutRecorder` needs.
struct SettingsRow<Icon: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var icon: Icon
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            icon
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
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
    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, subtitle: subtitle, icon: { EmptyView() }, trailing: trailing)
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
    let header: String
    let enableTitle: String
    let enableSubtitle: String
    let launcherSubtitle: String
    @Binding var isEnabled: Bool
    @Binding var showsInLauncher: Bool

    var body: some View {
        Section {
            Toggle(isOn: $isEnabled) {
                Text(enableTitle)
                Text(enableSubtitle)
            }
            Toggle(isOn: $showsInLauncher) {
                Text("Show in launcher")
                Text(launcherSubtitle)
            }
            // The switch above stays live so the feature can always be turned back on.
            .settingsEnabled(isEnabled)
        } header: {
            Text(header)
        }
    }
}

/// The filter row above a long list, shaped like a search field rather than a form text field.
struct SettingsFilterField: View {
    let prompt: String
    @Binding var query: String

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $query)
                .textFieldStyle(.plain)
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
    }
}
