import AppKit
import SwiftUI

struct BackupSettingsView: View {
    @ObservedObject private var runningApps = AppCore.shared.runningApps
    @State private var raycastFile: URL?
    @State private var passphrase = ""
    @State private var importing = false
    @State private var status: Status?
    @State private var selection: RaycastImportOptions = .all

    private enum Status {
        case success(String)
        case failure(String)
    }

    private var raycastRunning: Bool {
        runningApps.runningBundleIDs.contains(where: BackupActions.isRaycastBundleID)
    }

    var body: some View {
        SettingsPane(
            title: "Backup",
            subtitle: "Export your settings, restore a backup, or import from Raycast."
        ) {
            SettingsCard(header: "Smallcast") {
                SettingsRow(
                    title: "Export Settings",
                    subtitle: "Save your shortcuts, favorites, and preferences to a JSON file.",
                    systemImage: "square.and.arrow.up",
                    tint: .blue
                ) {
                    Button("Export…") { BackupActions.exportSettings() }
                        .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Import Settings",
                    subtitle:
                        "Restore from a Smallcast backup. Only values in the file are changed.",
                    systemImage: "square.and.arrow.down",
                    tint: .green
                ) {
                    Button("Import…") { BackupActions.importSettings() }
                        .controlSize(.small)
                }
            }

            SettingsCard(header: "Import from Raycast") {
                SettingsRow(
                    title: "Raycast Export",
                    subtitle: raycastFile?.lastPathComponent
                        ?? "Choose a .rayconfig file exported from Raycast.",
                    systemImage: "doc.badge.gearshape",
                    tint: .orange
                ) {
                    Button("Choose…") { chooseRaycastFile() }
                        .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Passphrase",
                    subtitle: "The password you set when exporting from Raycast.",
                    systemImage: "key",
                    tint: .gray
                ) {
                    SecureField("Passphrase", text: $passphrase)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .onSubmit(runRaycastImport)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Import",
                    subtitle: "Choose what to bring over, then import.",
                    systemImage: "arrow.down.circle",
                    tint: .indigo
                ) {
                    if importing {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Import") { runRaycastImport() }
                            .controlSize(.small)
                            .disabled(raycastFile == nil || passphrase.isEmpty || selection.isEmpty)
                    }
                }
                RaycastImportSelection(selection: $selection)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.bottom, Theme.Spacing.lg)
                conflictCallout
                if let status {
                    SettingsDivider()
                    statusRow(status)
                }
            }
        }
    }

    @ViewBuilder
    private var conflictCallout: some View {
        if raycastRunning {
            SettingsCallout(
                title: "Raycast is running — quit it to avoid hotkey conflicts.",
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange
            ) {
                Button("Quit Raycast") { BackupActions.quitRaycast() }
                    .controlSize(.small)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.lg)
        } else {
            SettingsCallout(
                title: "Tip: unset the matching Raycast shortcuts to avoid conflicts.",
                systemImage: "info.circle",
                tint: .secondary
            )
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.lg)
        }
    }

    @ViewBuilder
    private func statusRow(_ status: Status) -> some View {
        switch status {
        case .success(let message):
            SettingsRow(title: message, systemImage: "checkmark.circle.fill", tint: .green) {
                EmptyView()
            }
        case .failure(let message):
            SettingsRow(title: message, systemImage: "exclamationmark.triangle.fill", tint: .orange)
            {
                EmptyView()
            }
        }
    }

    private func chooseRaycastFile() {
        guard let url = BackupActions.pickRaycastFile() else { return }
        raycastFile = url
        status = nil
    }

    private func runRaycastImport() {
        guard let file = raycastFile, !passphrase.isEmpty, !selection.isEmpty, !importing else {
            return
        }
        importing = true
        status = nil
        Task {
            defer { importing = false }
            do {
                let outcome = try await BackupActions.importRaycast(
                    file: file, passphrase: passphrase, options: selection)
                var message = BackupActions.summaryText(outcome.summary)
                if outcome.clipboardImported > 0 {
                    message += " Imported \(outcome.clipboardImported) clipboard entries."
                }
                if outcome.missingImages > 0 {
                    message += " \(outcome.missingImages) images were unavailable and skipped."
                }
                status = .success(message)
                passphrase = ""
            } catch {
                status = .failure(error.localizedDescription)
            }
        }
    }
}
