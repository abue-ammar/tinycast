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
        guard settings.hyperKey != .none else { return "Remap one key to \(hyperGlyphs) held together." }
        return "\(settings.hyperKey.title) sends \(hyperGlyphs), shown as ✦ in shortcuts."
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
            }

            Section {
                Toggle(isOn: $settings.launchAtLogin) {
                    SettingsRowTitle(.generalGeneral, "Launch at login")
                }
                Toggle(isOn: $showInMenuBar) {
                    SettingsRowTitle(.generalGeneral, "Show in menu bar")
                    Text("Shortcuts still work when hidden.")
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
                    SettingsRowTitle(.generalAppearance, "Theme")
                }
                InterfaceSizeRow()
                WindowModeRow()
                Toggle(isOn: $settings.showFavoritesInCompactMode) {
                    SettingsRowTitle(.generalAppearance, "Show favorites in compact mode")
                    Text("Launch them with ⌘1–⌘5.")
                }
                .settingsEnabled(settings.compactMode)
                Picker(selection: $settings.paletteDisplay) {
                    ForEach(PaletteDisplay.allCases) { display in
                        Text(display.title).tag(display)
                    }
                } label: {
                    SettingsRowTitle(.generalAppearance, "Open on")
                    Text("Focused window asks for Accessibility on first use; otherwise falls back to mouse display.")
                }
                Toggle(isOn: $settings.paletteDraggable) {
                    SettingsRowTitle(.generalAppearance, "Drag to reposition")
                    Text("Drag the strip above the search field.")
                }
            } header: {
                SettingsSectionHeader(.generalAppearance)
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
                            "Remapping needs Accessibility access.",
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
                        Text("When \(settings.hyperKey.title) is pressed alone.")
                    }
                }

                Toggle(isOn: $settings.hyperKeyIncludesShift) {
                    SettingsRowTitle(.generalHyperKey, "Include Shift (⇧)")
                }
                // Flipping it re-points recorded chords, so it needs a chord to mean.
                .settingsEnabled(settings.hyperKey != .none)
            } header: {
                SettingsSectionHeader(.generalHyperKey)
            }

            Section {
                Picker(selection: $settings.calcNumberStyle) {
                    ForEach(CalcNumberStyle.allCases) { style in
                        let sample = core.regionNumberFormat.format(for: style).localized("1,234,567.89")
                        Text("\(style.title) (\(sample))").tag(style)
                    }
                } label: {
                    SettingsRowTitle(.generalCalculator, "Number format")
                    Text("With a decimal comma, ; separates arguments.")
                }
            } header: {
                SettingsSectionHeader(.generalCalculator)
            }

            Section {
                Toggle(isOn: $settings.launcherShowsSuggestions) {
                    SettingsRowTitle(.generalSearch, "Show suggestions")
                    Text("What you open most, while the search field is empty.")
                }
                Picker(selection: $settings.rootSearchSensitivity) {
                    ForEach(SearchSensitivity.allCases) { sensitivity in
                        Text(sensitivity.title).tag(sensitivity)
                    }
                } label: {
                    SettingsRowTitle(.generalSearch, "Search sensitivity")
                    Text("Lower finds names from scattered letters.")
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
            title: "Window mode", subtitle: "Choose how the launcher opens.",
            subtitleLineLimit: 2, alignment: .top, anchor: .generalAppearance
        ) {
            HStack(spacing: Theme.Spacing.md) {
                option("Compact", image: "WindowModeCompact", compact: true)
                option("Expanded", image: "WindowModeExpanded", compact: false)
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
            subtitle: "Scales the launcher and its panels, not Settings.",
            anchor: .generalAppearance
        ) {
            HStack(spacing: Theme.Spacing.xxs) {
                ForEach(InterfaceSize.allCases) { size in
                    segment(size)
                }
            }
        }
    }

    private func segment(_ size: InterfaceSize) -> some View {
        let selected = settings.interfaceSize == size
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.barControl, style: .continuous)
        return Button {
            settings.interfaceSize = size
        } label: {
            Text("Aa")
                .font(.system(size: Self.glyph[size] ?? 13, weight: .medium))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .frame(width: Theme.Size.interfaceSizeSegment, height: Theme.Size.settingsControlHeight)
                // Without this only the glyphs take the click, not the segment around them.
                .contentShape(shape)
                .background(shape.fill(selected ? Theme.Colors.controlSurface : Color.clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(size.title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .help(size.title)
    }
}
