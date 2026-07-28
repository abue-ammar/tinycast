import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject private var settings = AppCore.shared.settings
    @ObservedObject private var hyperTap = AppCore.shared.hyperKeyTap
    // Same UserDefaults key the `App` binds its `MenuBarExtra(isInserted:)` to — toggling here updates the menu-bar icon live, with no shared observable between them.
    @AppStorage(SettingsKey.showInMenuBar) private var showInMenuBar = true

    /// The Hyper modifier chord as prose glyphs, tracking the Include Shift toggle.
    private var hyperGlyphs: String { settings.hyperKeyIncludesShift ? "⌃⌥⇧⌘" : "⌃⌥⌘" }

    private var hyperStatusDot: Color? {
        switch hyperTap.status {
        case .off: return nil
        case .active: return .green
        case .needsAccessibility: return .orange
        }
    }

    private var hyperSubtitle: String {
        guard settings.hyperKey != .none else {
            return
                "Select a physical key to remap to the \(hyperGlyphs) modifier keys simultaneously."
        }
        var text =
            "Pressing \(settings.hyperKey.title) will trigger the left \(hyperGlyphs) modifier keys."
        if settings.hyperKeyReplacesGlyph {
            text += " Hyper Key shortcuts will be shown in Smallcast with ✦."
        }
        if hyperTap.status == .needsAccessibility {
            text += " Smallcast needs Accessibility access to remap keys."
        }
        return text
    }

    var body: some View {
        SettingsPane(
            title: "General",
            subtitle: "Global shortcuts and startup behaviour."
        ) {
            SettingsCard(header: "Global Shortcuts") {
                SettingsRow(
                    title: "App Launcher",
                    subtitle: "Summon the fuzzy app launcher.",
                    systemImage: "magnifyingglass",
                    tint: .blue
                ) {
                    ShortcutRecorder(action: .togglePalette)
                }
            }

            SettingsCard(header: "Hyper Key") {
                SettingsRow(
                    title: "Hyper Key",
                    subtitle: hyperSubtitle,
                    systemImage: "sparkle",
                    tint: .purple,
                    statusDot: hyperStatusDot
                ) {
                    if hyperTap.status == .needsAccessibility {
                        Button("Grant Access…") { Permissions.openAccessibilitySettings() }
                            .controlSize(.small)
                    }
                    Picker("", selection: $settings.hyperKey) {
                        ForEach(HyperKeyPhysicalKey.allCases) { key in
                            Text(key.title).tag(key)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: settings.hyperKey) { _, newKey in
                        // A Quick Press choice is meaningless for a different key.
                        settings.hyperKeyQuickPress = .none
                        if newKey != .none { Permissions.ensureAccessibility() }
                    }
                }
                if settings.hyperKey.hasOriginalFunction {
                    SettingsDivider()
                    SettingsRow(
                        title: "Quick Press",
                        subtitle:
                            "Select an action to perform when \(settings.hyperKey.title) is pressed without any other keys.",
                        systemImage: "hand.tap",
                        tint: .teal
                    ) {
                        Picker("", selection: $settings.hyperKeyQuickPress) {
                            Text("Does Nothing").tag(HyperKeyQuickPress.none)
                            if let original = settings.hyperKey.quickPressOriginalTitle {
                                Text(original).tag(HyperKeyQuickPress.originalKey)
                            }
                            Text("Trigger Escape").tag(HyperKeyQuickPress.escape)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                SettingsDivider()
                SettingsRow(
                    title: "Include Shift (⇧)",
                    subtitle: "Hyper Key will remap to the \(hyperGlyphs) modifier keys.",
                    systemImage: "shift",
                    tint: .indigo
                ) {
                    Toggle("", isOn: $settings.hyperKeyIncludesShift)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Replace occurrences of \(hyperGlyphs) with ✦",
                    subtitle: "Shortcuts containing the Hyper Key modifiers are shown with ✦.",
                    systemImage: "keyboard",
                    tint: .gray
                ) {
                    Toggle("", isOn: $settings.hyperKeyReplacesGlyph)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

            SettingsCard(header: "Appearance") {
                SettingsRow(
                    title: "Compact mode",
                    subtitle:
                        "Open the launcher as a slim search bar that expands into the full list as you type.",
                    systemImage: "macwindow",
                    tint: .blue
                ) {
                    Toggle("", isOn: $settings.compactMode)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Show favorites in compact mode",
                    subtitle: "Pin favorite app icons to the right of the compact bar (⌘1–⌘5 to launch).",
                    systemImage: "star",
                    tint: .yellow
                ) {
                    Toggle("", isOn: $settings.showFavoritesInCompactMode)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(!settings.compactMode)
                }
                .opacity(settings.compactMode ? 1 : 0.5)
            }

            SettingsCard(header: "General") {
                SettingsRow(
                    title: "Launch at login",
                    subtitle: "Start Smallcast automatically when you log in.",
                    systemImage: "power",
                    tint: .green
                ) {
                    Toggle("", isOn: $settings.launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Show in menu bar",
                    subtitle:
                        "Keep the Smallcast icon in the menu bar. Shortcuts still work when hidden.",
                    systemImage: "menubar.arrow.up.rectangle",
                    tint: .gray
                ) {
                    Toggle("", isOn: $showInMenuBar)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Pop to Root Search",
                    subtitle: "Reset to the launcher this long after the window closes.",
                    systemImage: "arrow.uturn.backward",
                    tint: .indigo
                ) {
                    Picker("", selection: $settings.popToRootTimeout) {
                        ForEach(PopToRootTimeout.allCases) { timeout in
                            Text(timeout.title).tag(timeout)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsDivider()
                SettingsRow(
                    title: "Welcome Guide",
                    subtitle: "Re-run the first-launch setup: shortcut, permissions, and Raycast import.",
                    systemImage: "sparkles",
                    tint: .yellow
                ) {
                    Button("Show…") { AppCore.shared.showOnboarding() }
                        .controlSize(.small)
                }
            }
        }
    }
}
