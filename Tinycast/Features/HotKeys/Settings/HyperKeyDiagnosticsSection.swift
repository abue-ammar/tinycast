import SwiftUI

struct HyperKeyDiagnosticsSection: View {
    let diagnostics: HyperKeyDiagnostics
    let refresh: () -> Void
    let restart: () -> Void

    var body: some View {
        Section {
            SettingsRow(title: String(localized: "Active")) { yesNo(diagnostics.isActive) }
            SettingsRow(title: String(localized: "Active Key")) {
                DiagnosticValue(
                    text: diagnostics.activeKeyTitle ?? String(localized: "None"),
                    tone: diagnostics.activeKeyTitle == nil ? .invalid : .valid)
            }
            SettingsRow(title: String(localized: "Event Tap")) { optional(diagnostics.eventTapEnabled) }
            SettingsRow(title: String(localized: "Run Loop Source")) {
                optional(diagnostics.runLoopSourceValid)
            }
            if let secureInput = diagnostics.secureInput {
                SettingsRow(
                    title: String(localized: "Secure Input"), subtitle: describe(secureInput),
                    subtitleLineLimit: 4
                ) {
                    DiagnosticValue(
                        text: String(localized: "Active"),
                        tone: diagnostics.secureInputCompatibilityActive ? .valid : .invalid)
                }
            }
            if diagnostics.isActive {
                SettingsRow(title: String(localized: "Remapped Keyboards"), alignment: .top) {
                    DiagnosticList(
                        items: remappedItems, empty: (String(localized: "None"), DiagnosticTone.neutral))
                }
            }
            SettingsRow(
                title: String(localized: "Conflicting Apps"),
                subtitle: String(localized: "Apps running now that also remap keys."),
                alignment: .top
            ) {
                DiagnosticList(items: conflictItems, empty: (String(localized: "None"), DiagnosticTone.valid))
            }
            SettingsRow(
                title: String(localized: "Karabiner Conflict"), subtitle: karabinerDetail,
                subtitleLineLimit: 2
            ) {
                DiagnosticValue(
                    text: diagnostics.karabinerConflict
                        ? String(localized: "Detected") : String(localized: "None"),
                    tone: diagnostics.karabinerConflict ? .invalid : .valid)
            }
            if !diagnostics.capsLockMappingConflicts.isEmpty {
                SettingsRow(
                    title: String(localized: "Caps Lock Mapping Conflicts"),
                    subtitle: String(
                        localized: """
                            Modifier Keys in System Settings remaps Caps Lock, which blocks the Hyper Key.
                            """),
                    subtitleLineLimit: 2, alignment: .top
                ) {
                    VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                        DiagnosticList(items: capsLockConflictItems, empty: nil)
                        Button("Open Keyboard Settings…") {
                            AppLauncher.openSettingsPane(bundleID: "com.apple.Keyboard-Settings.extension")
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text("Hyper Key Diagnostics")
                Spacer()
                Button("Restart Hyper Key", action: restart)
                Button("Refresh", action: refresh)
            }
        }
    }

    private var karabinerDetail: String {
        let keyboards = diagnostics.karabinerVirtualKeyboards
        return keyboards.isEmpty
            ? String(localized: "No Karabiner keyboard found.")
            : String(localized: "Karabiner keyboards: \(keyboards.joined(separator: ", "))")
    }

    private var remappedItems: [(String, DiagnosticTone)] {
        diagnostics.remappedKeyboards.map { ($0, DiagnosticTone.valid) }
    }

    private var conflictItems: [(String, DiagnosticTone)] {
        diagnostics.conflictingApps.map { app in
            (app.name, app.severity == .blocking ? DiagnosticTone.invalid : DiagnosticTone.warning)
        }
    }

    private var capsLockConflictItems: [(String, DiagnosticTone)] {
        diagnostics.capsLockMappingConflicts.map { ($0, DiagnosticTone.invalid) }
    }

    private func yesNo(_ flag: Bool) -> DiagnosticValue {
        DiagnosticValue(
            text: flag ? String(localized: "Yes") : String(localized: "No"), tone: flag ? .valid : .invalid)
    }

    private func optional(_ flag: Bool?) -> DiagnosticValue {
        guard let flag else { return DiagnosticValue(text: String(localized: "N/A"), tone: .neutral) }
        return yesNo(flag)
    }

    /// macOS often names the wrong holder, so the likely ones lead and its claim is hedged.
    private func describe(_ secureInput: HyperKeyDiagnostics.SecureInput) -> String {
        var sentences = [
            diagnostics.secureInputCompatibilityActive
                ? String(localized: "Tinycast's Hyper shortcuts use Right Control while Secure Input is on.")
                : String(localized: "Key presses can't reach the Hyper Key while Secure Input is on.")
        ]
        if !secureInput.likelyOwners.isEmpty {
            sentences.append(
                String(localized: "Probably \(secureInput.likelyOwners.formatted(.list(type: .or)))."))
        }
        if let owner = secureInput.reportedOwner {
            sentences.append(String(localized: "macOS names \(owner), which isn't always right."))
        }
        if !diagnostics.secureInputCompatibilityActive {
            sentences.append(
                secureInput.ownerIsLoginWindow
                    ? String(localized: "Logging out and back in turns off Secure Input.")
                    : String(localized: "Closing that app turns off Secure Input."))
        }
        return sentences.joined(separator: " ")
    }

    private enum DiagnosticTone {
        case valid, invalid, warning, neutral

        var color: Color {
            switch self {
            case .valid: return Theme.Colors.success
            case .invalid: return Theme.Colors.destructive
            case .warning: return Theme.Colors.warning
            case .neutral: return .secondary
            }
        }
    }

    private struct DiagnosticValue: View {
        let text: String
        let tone: DiagnosticTone

        var body: some View {
            HStack(spacing: Theme.Spacing.sm) {
                Text(text).foregroundStyle(tone.color)
                ColorDot(color: tone.color)
            }
        }
    }

    private struct DiagnosticList: View {
        let items: [(String, DiagnosticTone)]
        let empty: (String, DiagnosticTone)?

        var body: some View {
            VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                if items.isEmpty, let empty {
                    DiagnosticValue(text: empty.0, tone: empty.1)
                }
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    DiagnosticValue(text: item.0, tone: item.1)
                }
            }
        }
    }
}
