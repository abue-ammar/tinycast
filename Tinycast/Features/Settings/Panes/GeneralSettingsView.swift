import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    private var hyperTap: HyperKeyTap { core.hyperKeyTap }
    private var launcherRanking: LauncherRankingStore { core.launcherRanking }
    // The same key `MenuBarExtra(isInserted:)` binds, so this updates the icon live.
    @AppStorage(SettingsKey.showInMenuBar) private var showInMenuBar = true
    @State private var confirmingRankingReset = false
    @State private var inputSources: [InputSourceSwitcher.Option] = []

    /// The Hyper modifier chord as prose glyphs, tracking the Include Shift toggle.
    private var hyperGlyphs: String { settings.hyperKeyIncludesShift ? "⌃⌥⇧⌘" : "⌃⌥⌘" }

    /// The missing-permission half is its own row, so it can carry the button that fixes it.
    private var hyperSubtitle: String {
        guard settings.hyperKey != .none else {
            return
                "Select a physical key to remap to the \(hyperGlyphs) modifier keys simultaneously."
        }
        return
            "Pressing \(settings.hyperKey.title) will trigger the left \(hyperGlyphs) modifier keys."
            + " Hyper Key shortcuts are shown in Tinycast with ✦."
    }

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                SettingsRow(title: "App Launcher", anchor: .generalGlobalShortcuts) {
                    ShortcutRecorder(action: .togglePalette)
                }
            } header: {
                SettingsSectionHeader(.generalGlobalShortcuts)
            } footer: {
                Text("Summon the fuzzy app launcher.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent {
                    Button("Reset…", role: .destructive) {
                        confirmingRankingReset = true
                    }
                    .disabled(launcherRanking.isEmpty)
                } label: {
                    SettingsRowTitle(.generalSearch, "Learned ranking")
                }
            } header: {
                SettingsSectionHeader(.generalSearch)
            } footer: {
                Text(
                    "Tinycast privately learns which results you choose for each query. Reset all learned choices to restore the default order."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Picker(selection: $settings.hyperKey) {
                    ForEach(HyperKeyPhysicalKey.allCases) { key in
                        Text(key.title).tag(key)
                    }
                } label: {
                    SettingsRowTitle(.generalHyperKey, "Hyper Key")
                    Text(hyperSubtitle)
                }
                .onChange(of: settings.hyperKey) { _, newKey in
                    // A Quick Press choice is meaningless for a different key.
                    settings.hyperKeyQuickPress = .none
                    if newKey != .none { Permissions.ensureAccessibility() }
                }

                if hyperTap.status == .needsAccessibility {
                    LabeledContent {
                        Button("Grant Access…") { Permissions.openAccessibilitySettings() }
                    } label: {
                        Label(
                            "Tinycast needs Accessibility access to remap keys.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.orange)
                    }
                }

                if settings.hyperKey.hasOriginalFunction {
                    Picker(selection: $settings.hyperKeyQuickPress) {
                        Text("Does Nothing").tag(HyperKeyQuickPress.none)
                        if let original = settings.hyperKey.quickPressOriginalTitle {
                            Text(original).tag(HyperKeyQuickPress.originalKey)
                        }
                        Text("Trigger Escape").tag(HyperKeyQuickPress.escape)
                    } label: {
                        SettingsRowTitle(.generalHyperKey, "Quick Press")
                        Text(
                            "Select an action to perform when \(settings.hyperKey.title) is pressed without any other keys."
                        )
                    }
                }

                Toggle(isOn: $settings.hyperKeyIncludesShift) {
                    SettingsRowTitle(.generalHyperKey, "Include Shift (⇧)")
                    Text("Hyper Key will remap to the \(hyperGlyphs) modifier keys.")
                }
                // Flipping it re-points recorded chords, so it needs a chord to mean.
                .settingsEnabled(settings.hyperKey != .none)
            } header: {
                SettingsSectionHeader(.generalHyperKey)
            }

            Section {
                Picker(selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                } label: {
                    SettingsRowTitle(.generalAppearance, "Theme")
                    Text("Match macOS, or pin Tinycast to Light or Dark.")
                }
                Toggle(isOn: $settings.compactMode) {
                    SettingsRowTitle(.generalAppearance, "Compact mode")
                    Text(
                        "Open the launcher as a slim search bar that expands into the full list as you type."
                    )
                }
                Toggle(isOn: $settings.showFavoritesInCompactMode) {
                    SettingsRowTitle(.generalAppearance, "Show favorites in compact mode")
                    Text("Pin favorite app icons to the right of the compact bar (⌘1–⌘5 to launch).")
                }
                .disabled(!settings.compactMode)
                Toggle(isOn: $settings.openOnCursorScreen) {
                    SettingsRowTitle(.generalAppearance, "Follow the cursor across displays")
                    Text(
                        "Open the launcher on whichever display the pointer is on, rather than the one with the menu bar."
                    )
                }
                Toggle(isOn: $settings.paletteDraggable) {
                    SettingsRowTitle(.generalAppearance, "Drag to reposition")
                    Text(
                        "Grab the thin strip just above the search field to move the launcher out of the way."
                    )
                }
            } header: {
                SettingsSectionHeader(.generalAppearance)
            }

            Section {
                Toggle(isOn: $settings.launchAtLogin) {
                    SettingsRowTitle(.generalGeneral, "Launch at login")
                    Text("Start Tinycast automatically when you log in.")
                }
                Toggle(isOn: $showInMenuBar) {
                    SettingsRowTitle(.generalGeneral, "Show in menu bar")
                    Text("Keep the Tinycast icon in the menu bar. Shortcuts still work when hidden.")
                }
                Picker(selection: $settings.popToRootTimeout) {
                    ForEach(PopToRootTimeout.allCases) { timeout in
                        Text(timeout.title).tag(timeout)
                    }
                } label: {
                    SettingsRowTitle(.generalGeneral, "Pop to Root Search")
                    Text("Reset to the launcher this long after the window closes.")
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
                        Text("Switch the keyboard to this source while the launcher is open.")
                    }
                }
            } header: {
                SettingsSectionHeader(.generalGeneral)
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
