import AppKit
import SwiftUI

struct BackupSettingsView: View {
    @Environment(AppCore.self) private var core
    private var runningApps: RunningAppsMonitor { core.runningApps }
    @State private var raycastFile: URL?
    @State private var passphrase = ""
    @State private var importing = false
    @State private var status: Status?
    @State private var selection: RaycastImportOptions = .all
    @State private var isRaycastExport = false
    @State private var exportSelection = BackupCategory.all
    @State private var importSelection: Set<BackupCategory> = []
    @State private var exporting = false
    @State private var importingBackup = false
    @State private var backupStatus: Status?
    @State private var backupFile: URL?
    @State private var openedManifest: BackupManifest?
    /// Held between opening the file and applying it, so the extracted tree survives the picker.
    @State private var openedStaging: BackupStaging?

    private enum Status {
        case success(String)
        case failure(String)
    }

    private var raycastRunning: Bool {
        runningApps.runningBundleIDs.contains(where: BackupActions.isRaycastBundleID)
    }

    private var raycastFileSubtitle: String {
        guard let name = raycastFile?.lastPathComponent else {
            return "Choose a .rayconfig file exported from Raycast."
        }
        return "\(name) — \(isRaycastExport ? "Raycast export" : "not a Raycast export")"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    if exporting {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Export…") { runExport() }.disabled(exportSelection.isEmpty)
                    }
                } label: {
                    SettingsRowTitle(.backupExport, "Export Backup")
                    Text("Choose what to include, then save it as a single .tinycast file.")
                }
                BackupCategorySelection(selection: $exportSelection)
                if let backupStatus { statusRow(backupStatus) }
            } header: {
                SettingsSectionHeader(.backupExport)
            }

            Section {
                LabeledContent {
                    Button("Choose…") { chooseBackupFile() }
                } label: {
                    SettingsRowTitle(.backupImport, "Backup File")
                    Text(backupFileSubtitle)
                }
                if let manifest = openedManifest {
                    BackupCategorySelection(
                        selection: $importSelection, available: available(in: manifest))
                    LabeledContent {
                        if importingBackup {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Import") { runBackupImport() }
                                .disabled(importSelection.isEmpty)
                        }
                    } label: {
                        Text("Import")
                        Text("Only the categories you tick are restored.")
                    }
                }
            } header: {
                SettingsSectionHeader(.backupImport)
            }

            Section {
                LabeledContent {
                    Button("Choose…") { chooseRaycastFile() }
                } label: {
                    SettingsRowTitle(.backupImportFromRaycast, "Raycast Export")
                    Text(raycastFileSubtitle)
                }
                LabeledContent {
                    SecureField("Passphrase", text: $passphrase)
                        .frame(width: 160)
                        .onSubmit(runRaycastImport)
                } label: {
                    Text("Passphrase")
                    Text("The password you set when exporting from Raycast.")
                }
                LabeledContent {
                    if importing {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Import") { runRaycastImport() }
                            .disabled(!isRaycastExport || passphrase.isEmpty || selection.isEmpty)
                    }
                } label: {
                    Text("Import")
                    Text("Choose what to bring over, then import.")
                }
                RaycastImportSelection(selection: $selection)
                conflictNotice
                if let status { statusRow(status) }
            } header: {
                SettingsSectionHeader(.backupImportFromRaycast)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.backup)
        .onDisappear { if !importingBackup { discardStagedBackup() } }
    }

    @ViewBuilder
    private var conflictNotice: some View {
        if raycastRunning {
            LabeledContent {
                Button("Quit Raycast") { BackupActions.quitRaycast() }
            } label: {
                Label(
                    "Raycast is running — quit it to avoid hotkey conflicts.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
            }
        } else {
            Label(
                "Tip: unset the matching Raycast shortcuts to avoid conflicts.",
                systemImage: "info.circle"
            )
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func statusRow(_ status: Status) -> some View {
        switch status {
        case .success(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private var backupFileSubtitle: String {
        guard let name = backupFile?.lastPathComponent else {
            return "Choose a .tinycast file exported from Tinycast."
        }
        return openedManifest == nil ? "\(name) — couldn't be read" : name
    }

    private func available(in manifest: BackupManifest) -> [BackupCategory: Int] {
        Dictionary(
            uniqueKeysWithValues: BackupCategory.ordered(manifest.categories).map {
                ($0, manifest.count($0))
            })
    }

    private func runExport() {
        guard !exporting else { return }
        exporting = true
        backupStatus = nil
        let categories = exportSelection
        Task {
            defer { exporting = false }
            do {
                let result = try await BackupActions.exportBackup(
                    core: core, categories: categories)
                backupStatus = .success(BackupActions.exportText(result))
            } catch is CancellationError {
                // The user closed the save panel; nothing to report.
            } catch {
                backupStatus = .failure(error.localizedDescription)
            }
        }
    }

    private func chooseBackupFile() {
        guard let url = BackupActions.chooseBackupFile() else { return }
        discardStagedBackup()
        backupFile = url
        backupStatus = nil
        Task {
            do {
                let (staging, manifest) = try await BackupActions.openBackup(at: url)
                openedStaging = staging
                openedManifest = manifest
                importSelection = manifest.categories
            } catch {
                backupStatus = .failure(error.localizedDescription)
            }
        }
    }

    private func runBackupImport() {
        guard let staging = openedStaging, !importingBackup, !importSelection.isEmpty else {
            return
        }
        importingBackup = true
        let categories = importSelection
        Task {
            defer { importingBackup = false }
            let summary = await BackupActions.applyBackup(
                categories, from: staging, to: core)
            // Staged files are adopted by the stores during apply, so the tree goes either way.
            discardStagedBackup()
            backupFile = nil
            if let summary { backupStatus = .success(BackupActions.summaryText(summary)) }
        }
    }

    /// The extracted tree can run to gigabytes, so leaving the pane must not strand it.
    private func discardStagedBackup() {
        openedStaging?.discard()
        openedStaging = nil
        openedManifest = nil
    }

    private func chooseRaycastFile() {
        guard let url = BackupActions.pickRaycastFile() else { return }
        raycastFile = url
        isRaycastExport = BackupActions.isRaycastExport(url)
        status = nil
    }

    private func runRaycastImport() {
        guard let file = raycastFile, isRaycastExport, !passphrase.isEmpty, !selection.isEmpty,
            !importing
        else { return }
        importing = true
        status = nil
        Task {
            defer { importing = false }
            do {
                let outcome = try await BackupActions.importRaycast(
                    core: core, file: file, passphrase: passphrase, options: selection)
                var parts: [String] = []
                if let applied = BackupActions.appliedText(outcome.summary) { parts.append(applied) }
                if outcome.clipboardImported > 0 {
                    parts.append("Imported \(outcome.clipboardImported) clipboard entries.")
                }
                if outcome.snippetsImported > 0 {
                    let noun = outcome.snippetsImported == 1 ? "snippet" : "snippets"
                    parts.append("Imported \(outcome.snippetsImported) \(noun).")
                }
                if let snippetsError = outcome.snippetsError {
                    parts.append("Couldn’t import snippets: \(snippetsError)")
                }
                var message =
                    parts.isEmpty
                    ? BackupActions.nothingImportedText : parts.joined(separator: " ")
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
