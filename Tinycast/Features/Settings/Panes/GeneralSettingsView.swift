import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    private var launcherRanking: LauncherRankingStore { core.launcherRanking }
    @State private var confirmingRankingReset = false
    @State private var inputSources: [InputSourceSwitcher.Option] = []

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                SettingsRow(title: "Show Launcher", anchor: .generalGlobalShortcuts) {
                    ShortcutRecorder(action: .togglePalette)
                }
            } header: {
                SettingsSectionHeader(.generalGlobalShortcuts)
            }

            Section {
                Picker(selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(verbatim: language.title).tag(language)
                    }
                } label: {
                    SettingsRowTitle(.generalGeneral, "Language")
                }
                Toggle(isOn: $settings.launchAtLogin) {
                    SettingsRowTitle(.generalGeneral, "Launch at login")
                }
                Toggle(isOn: $settings.showInMenuBar) {
                    SettingsRowTitle(.generalGeneral, "Show in menu bar")
                    Text("Shortcuts still work when the menu bar icon is hidden.")
                }
                Toggle(isOn: $settings.automaticallyCheckForUpdates) {
                    SettingsRowTitle(.generalGeneral, "Automatically check for updates")
                    Text("You can still check for updates manually.")
                }
                Picker(selection: $settings.popToRootTimeout) {
                    ForEach(PopToRootTimeout.allCases) { timeout in
                        Text(timeout.title).tag(timeout)
                    }
                } label: {
                    SettingsRowTitle(.generalGeneral, "Pop to Root Search")
                    Text("After the launcher closes.")
                }
                Picker(selection: $settings.escapeKeyBehavior) {
                    ForEach(EscapeKeyBehavior.allCases) { behavior in
                        Text(behavior.title).tag(behavior)
                    }
                } label: {
                    SettingsRowTitle(.generalGeneral, "Escape Key Behavior")
                    Text("When the search field is empty.")
                }
                // Empty only when TIS fails; one layout still lists, so the row stays put.
                if !inputSources.isEmpty {
                    Picker(selection: $settings.autoSwitchInputSourceID) {
                        Text("None").tag(nil as String?)
                        ForEach(inputSources) { source in
                            Text(source.title).tag(Optional(source.id))
                        }
                    } label: {
                        SettingsRowTitle(.generalGeneral, "Auto-switch input source")
                        Text("While the launcher is open.")
                    }
                }
            } header: {
                SettingsSectionHeader(.generalGeneral)
            }

            Section {
                Picker(selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                } label: {
                    SettingsRowTitle(.generalAppearance, "Appearance")
                }
                Toggle(isOn: $settings.animationsEnabled) {
                    SettingsRowTitle(.generalAppearance, "Show animations")
                }
                InterfaceSizeRow()
                WindowModeRow()
                    .background {
                        if !settings.compactMode {
                            Color.clear.settingsAnchor(.generalCompactShortcuts)
                        }
                    }
                Toggle(isOn: $settings.openOnCursorScreen) {
                    SettingsRowTitle(.generalAppearance, "Follow the cursor across displays")
                }
                Toggle(isOn: $settings.paletteDraggable) {
                    SettingsRowTitle(.generalAppearance, "Drag to move the launcher")
                    Text("Move the launcher by dragging the search bar.")
                }
            } header: {
                SettingsSectionHeader(.generalAppearance)
            }

            if settings.compactMode { CompactShortcutsSection() }

            HyperKeySettingsSection()

            Section {
                Picker(selection: $settings.calcNumberStyle) {
                    ForEach(CalcNumberStyle.allCases) { style in
                        let sample = core.regionNumberFormat.format(for: style).localized("1,234,567.89")
                        Text(verbatim: "\(style.title) (\(sample))").tag(style)
                    }
                } label: {
                    SettingsRowTitle(.generalCalculator, "Number format")
                    Text("With a decimal comma, use ; to separate arguments.")
                }
            } header: {
                SettingsSectionHeader(.generalCalculator)
            }

            Section {
                Toggle(isOn: $settings.launcherShowsSuggestions) {
                    SettingsRowTitle(.generalSearch, "Show suggestions")
                    Text("Shows your most-used items when the search field is empty.")
                }
                Picker(selection: $settings.rootSearchSensitivity) {
                    ForEach(SearchSensitivity.allCases) { sensitivity in
                        Text(sensitivity.title).tag(sensitivity)
                    }
                } label: {
                    SettingsRowTitle(.generalSearch, "Search sensitivity")
                    Text("A lower value allows less exact matches.")
                }
                LabeledContent {
                    Button("Reset…", role: .destructive) {
                        confirmingRankingReset = true
                    }
                    .disabled(launcherRanking.isEmpty)
                } label: {
                    SettingsRowTitle(.generalSearch, "Learned ranking")
                    Text("Learned privately from the results you pick.")
                }
            } header: {
                SettingsSectionHeader(.generalSearch)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.general)
        .confirmationDialog(
            "Reset learned launcher ranking?",
            isPresented: $confirmingRankingReset,
            titleVisibility: .visible
        ) {
            Button("Reset Ranking", role: .destructive) {
                launcherRanking.resetAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Tinycast will relearn your preferred results as you use the launcher.")
        }
        .onAppear(perform: refreshInputSources)
        .onReceive(
            DistributedNotificationCenter.default().publisher(
                for: InputSourceSwitcher.sourcesDidChange)
        ) { _ in
            refreshInputSources()
        }
    }

    private func refreshInputSources() {
        inputSources = core.inputSourceSwitcher.options(selecting: settings.autoSwitchInputSourceID)
    }
}

private struct WindowModeRow: View {
    @Environment(AppSettings.self) private var settings

    private static let preview = CGSize(width: 135, height: 80)

    var body: some View {
        SettingsRow(
            title: "Window mode",
            subtitle: String(localized: "Choose how the launcher opens."),
            subtitleLineLimit: 2, alignment: .top, anchor: .generalAppearance
        ) {
            HStack(spacing: Theme.Spacing.md) {
                option(String(localized: "Compact"), image: "WindowModeCompact", compact: true)
                option(String(localized: "Expanded"), image: "WindowModeExpanded", compact: false)
            }
        }
    }

    private func option(_ title: String, image: String, compact: Bool) -> some View {
        let selected = settings.compactMode == compact
        return Button {
            settings.compactMode = compact
        } label: {
            VStack(spacing: Theme.Spacing.xs) {
                Image(image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: Self.preview.width, height: Self.preview.height)
                    .clipShape(
                        RoundedRectangle(cornerRadius: Theme.Radius.barControl, style: .continuous)
                    )
                    .saturation(selected ? 1 : 0)
                Text(title)
                    .font(.caption)
                    .fontWeight(selected ? .semibold : .regular)
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(WindowModeButtonStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private struct WindowModeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressedLabel(configuration: configuration)
    }

    private struct PressedLabel: View {
        let configuration: ButtonStyle.Configuration
        @State private var showsPressed = false

        var body: some View {
            configuration.label
                .opacity(showsPressed ? 0.7 : 1)
                .task(id: configuration.isPressed) {
                    if configuration.isPressed {
                        try? await Task.sleep(for: .milliseconds(20))
                        guard !Task.isCancelled else { return }
                        showsPressed = true
                    } else {
                        showsPressed = false
                    }
                }
        }
    }
}

/// Three glyph steps read as a legend; a true-to-scale "Aa" would look identical at 1.1.
private struct InterfaceSizeRow: View {
    @Environment(AppSettings.self) private var settings

    private static let glyph: [InterfaceSize: CGFloat] = [
        .standard: 11, .large: 14, .larger: 17
    ]

    var body: some View {
        SettingsRow(
            title: "Interface size",
            subtitle: String(localized: "Resizes the launcher and its panels, but not Settings."),
            anchor: .generalAppearance
        ) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(InterfaceSize.allCases) { size in
                    segment(size)
                }
            }
        }
    }

    private func segment(_ size: InterfaceSize) -> some View {
        let selected = settings.interfaceSize == size
        return Button {
            settings.interfaceSize = size
        } label: {
            Text(verbatim: "Aa")
                .font(.system(size: Self.glyph[size] ?? 13, weight: .medium))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .settingsOptionSegment(isSelected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(size.title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .help(size.title)
    }
}
