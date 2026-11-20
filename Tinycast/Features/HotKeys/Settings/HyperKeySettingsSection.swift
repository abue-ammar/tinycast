import SwiftUI

struct HyperKeySettingsSection: View {
    @Environment(MainAppLink.self) private var mainApp
    @Environment(AppSettings.self) private var settings
    @State private var showsDiagnostics = false

    /// The main app runs the key, so it alone can say how it is doing.
    private var hyperKey: MainAppStatus.HyperKey { mainApp.status.hyperKey }

    private var hyperGlyphs: String { settings.hyperKeyIncludesShift ? "⌃⌥⇧⌘" : "⌃⌥⌘" }

    /// Only a choice made here resets Quick Press: settings.json may set both keys at once.
    private var hyperKeySelection: Binding<HyperKeyPhysicalKey> {
        Binding(
            get: { settings.hyperKey },
            set: { key in
                guard key != settings.hyperKey else { return }
                settings.hyperKey = key
                // A Quick Press choice is meaningless for a different key.
                settings.hyperKeyQuickPress = .none
                if key != .none { Permissions.ensureAccessibility() }
            })
    }

    private var hyperSubtitle: String {
        guard settings.hyperKey != .none else {
            return String(localized: "Use one key to hold \(hyperGlyphs) together.")
        }
        return String(
            localized: "\(settings.hyperKey.title) sends \(hyperGlyphs), shown as ✦ in shortcuts.")
    }

    var body: some View {
        @Bindable var settings = settings
        Section {
            Picker(selection: hyperKeySelection) {
                ForEach(HyperKeyPhysicalKey.allCases) { key in
                    Text(key.title).tag(key)
                }
            } label: {
                SettingsRowTitle(.generalHyperKey, "Hyper Key")
                Text(hyperSubtitle)
            }

            if settings.hyperKey != .none {
                HyperKeyStatusRow(
                    status: hyperKey.status, takeover: hyperKey.takeover,
                    isShowingDiagnostics: showsDiagnostics
                ) {
                    showsDiagnostics.toggle()
                    mainApp.send(.inspectHyperKey(diagnostics: showsDiagnostics))
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
                    Text("When you press and release \(settings.hyperKey.title) on its own.")
                }
            }

            Toggle(isOn: $settings.hyperKeyIncludesShift) {
                SettingsRowTitle(.generalHyperKey, "Include Shift (⇧)")
            }
            // Flipping it re-points recorded chords, so it needs a chord to mean.
            .settingsEnabled(settings.hyperKey != .none)

            if settings.hyperKey.supportsSecureInputCompatibility {
                Toggle(isOn: $settings.hyperKeySecureInputCompatibility) {
                    SettingsRowTitle(.generalHyperKey, "Secure Input Compatibility")
                    Text(
                        """
                        Tinycast's Hyper shortcuts also work in password fields and secure terminals, \
                        where Right Control (⌃) with the same key triggers them. \
                        While on, Right Control (⌃) acts as the Hyper Key too.
                        """)
                }
            }
        } header: {
            SettingsSectionHeader(.generalHyperKey)
        }
        .onAppear { mainApp.send(.inspectHyperKey(diagnostics: showsDiagnostics)) }
        .onChange(of: hyperKey.status) { mainApp.send(.inspectHyperKey(diagnostics: showsDiagnostics)) }

        if showsDiagnostics, let diagnostics = hyperKey.diagnostics, settings.hyperKey != .none {
            HyperKeyDiagnosticsSection(
                diagnostics: diagnostics,
                refresh: { mainApp.send(.inspectHyperKey(diagnostics: true)) },
                restart: { mainApp.send(.restartHyperKey) })
        }
    }

    private struct HyperKeyStatusRow: View {
        let status: HyperKeyManager.Status
        let takeover: HyperKeyDiagnostics.Takeover?
        let isShowingDiagnostics: Bool
        let toggleDiagnostics: () -> Void

        var body: some View {
            SettingsRow(title: String(localized: "Status"), subtitle: detail, subtitleLineLimit: 3) {
                HStack(spacing: Theme.Spacing.sm) {
                    ColorDot(color: tint)
                    Text(title).foregroundStyle(.secondary)
                    if status == .needsAccessibility {
                        Button("Grant Access…") { Permissions.openAccessibilitySettings() }
                    }
                    Button(
                        isShowingDiagnostics ? "Hide Diagnostics" : "Diagnostics…", action: toggleDiagnostics)
                }
            }
        }

        private var title: String {
            if takeover != nil { return String(localized: "Taken Over") }
            switch status {
            case .off: return String(localized: "Off")
            case .active: return String(localized: "Active")
            case .needsAccessibility: return String(localized: "Needs Accessibility")
            case .blocked: return String(localized: "Blocked")
            case .remapUnavailable: return String(localized: "Unavailable")
            case .paused: return String(localized: "Paused")
            }
        }

        private var detail: String? {
            if let takeover { return describe(takeover) }
            switch status {
            case .blocked(let appName):
                return String(localized: "\(appName) runs its own Hyper Key. Quit it to use this one.")
            case .remapUnavailable: return String(localized: "macOS refused to remap the keyboard.")
            case .paused:
                return String(
                    localized: "The key works normally during sleep, screen lock or user switching.")
            case .off, .active, .needsAccessibility: return nil
            }
        }

        private var tint: Color {
            if takeover != nil { return Theme.Colors.destructive }
            switch status {
            case .active: return Theme.Colors.success
            case .needsAccessibility, .paused: return Theme.Colors.warning
            case .off, .blocked, .remapUnavailable: return Theme.Colors.destructive
            }
        }

        private func describe(_ takeover: HyperKeyDiagnostics.Takeover) -> String {
            let keyboards = takeover.keyboards.formatted(.list(type: .and))
            var sentences = [String(localized: "Another app now remaps Caps Lock on \(keyboards).")]
            if !takeover.likelyApps.isEmpty {
                sentences.append(
                    String(localized: "Probably \(takeover.likelyApps.formatted(.list(type: .or)))."))
            }
            return sentences.joined(separator: " ")
        }
    }
}
