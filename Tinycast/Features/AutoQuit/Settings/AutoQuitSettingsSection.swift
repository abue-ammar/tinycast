import SwiftUI

struct AutoQuitSettingsSection: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Section {
            Picker(selection: $settings.autoQuitMinutes) {
                ForEach(AutoQuitMinutes.allCases) { minutes in
                    Text(verbatim: minutes.title).tag(minutes)
                }
            } label: {
                SettingsRowTitle(.applicationsAutoQuit, "Default duration")
                Text("Apps set to Default follow this.")
            }
            AutoQuitRulesList(
                rules: $settings.autoQuitRules, defaultMinutes: settings.autoQuitMinutes)
        } header: {
            SettingsSectionHeader(.applicationsAutoQuit)
        } footer: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Quits these apps after they sit in the background.")
                Text(
                    "Finder and Tinycast are never quit, and a recording or playback in Music or Spotify postpones it."
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct AutoQuitRulesList: View {
    @Binding var rules: [AutoQuitRule]
    let defaultMinutes: AutoQuitMinutes

    @Environment(AppIndex.self) private var appIndex
    @State private var picking = false

    private var excluded: Set<String> {
        var ids = Set(rules.map(\.bundleID))
        ids.insert(AutoQuitSchedule.finderBundleID)
        if let own = Bundle.main.bundleIdentifier { ids.insert(own) }
        return ids
    }

    var body: some View {
        ForEach($rules) { $rule in
            AutoQuitRuleRow(rule: $rule, defaultMinutes: defaultMinutes) {
                rules.removeAll { $0.bundleID == rule.bundleID }
            }
        }
        Button("Add Application…") { picking = true }
            .popover(isPresented: $picking, arrowEdge: .bottom) {
                AppPickerPopover(excluded: excluded) { bundleID in
                    rules.append(AutoQuitRule(bundleID: bundleID, minutes: nil))
                    picking = false
                }
            }
    }
}

private struct AutoQuitRuleRow: View {
    @Binding var rule: AutoQuitRule
    let defaultMinutes: AutoQuitMinutes
    let onRemove: () -> Void

    @Environment(AppIndex.self) private var appIndex

    var body: some View {
        let (name, icon) = AppPresentation.resolve(bundleID: rule.bundleID, in: appIndex)
        LabeledContent {
            HStack(spacing: Theme.Spacing.md) {
                if rule.minutes == nil {
                    Text(verbatim: defaultMinutes.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker(selection: $rule.minutes) {
                    Text("Default").tag(AutoQuitMinutes?.none)
                    ForEach(AutoQuitMinutes.allCases) { minutes in
                        Text(verbatim: minutes.title).tag(Optional(minutes))
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityLabel("Duration for \(name)")
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(name) from Auto Quit")
            }
        } label: {
            Label {
                Text(name).lineLimit(1)
            } icon: {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: SettingsListMetrics.iconSize, height: SettingsListMetrics.iconSize)
            }
        }
    }
}
