import AppKit
import SwiftUI

struct BackupSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(MainAppLink.self) private var mainApp
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
    @State private var preview: BackupPreview?
    @State private var preparingBackup: Task<Void, Never>?

    private enum Status {
        case success(String)
        case failure(String)
    }

    private var raycastRunning: Bool {
        runningApps.runningBundleIDs.contains(where: BackupActions.isRaycastBundleID)
    }

    /// Turning it on may ask first, so the switch follows the setting rather than the click.
    private var settingsFileSync: Binding<Bool> {
        Binding(
            get: { core.settings.settingsFileEnabled },
            set: { enabled in
                Task {
                    guard let change = await BackupActions.settingsFileChange(enabling: enabled, core: core)
                    else { return }
                    mainApp.send(.setSettingsFile(change))
                }
            })
    }

    private var raycastFileSubtitle: String {
        guard let name = raycastFile?.lastPathComponent else {
            return String(localized: "A .rayconfig file from Raycast 2.0 or later.")
        }
        return isRaycastExport
            ? String(localized: "\(name) — Raycast export")
            : String(localized: "\(name) — not a Raycast export")
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
                    Text("The ticked items, as one .tinycast file.")
                }
                BackupCategorySelection(selection: $exportSelection)
                if let backupStatus { statusRow(backupStatus) }
            } header: {
                SettingsSectionHeader(.backupExport)
            }

            Section {
                LabeledContent {
                    Button("Choose…") { chooseBackupFile() }
                        .disabled(importingBackup || preparingBackup != nil)
                } label: {
                    SettingsRowTitle(.backupImport, "Backup File")
                    Text(backupFileSubtitle)
                }
                if let manifest = preview?.manifest {
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
                    RevealableSecureField(
                        title: String(localized: "Passphrase"), text: $passphrase,
                        prompt: Text("Export password")
                    )
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    // LabeledContent right-aligns its value text, caret and all; a field reads left.
                    .multilineTextAlignment(.leading)
                    .frame(width: 160)
                    .onSubmit(runRaycastImport)
                } label: {
                    Text("Passphrase")
                }
                RaycastImportSelection(selection: $selection)
                conflictNotice
                LabeledContent {
                    if importing {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Import") { runRaycastImport() }
                            .disabled(!isRaycastExport || passphrase.isEmpty || selection.isEmpty)
                    }
                } label: {
                    Text("Import")
                }
                if let status { statusRow(status) }
            } header: {
                SettingsSectionHeader(.backupImportFromRaycast)
            }

            Section {
                Toggle(isOn: settingsFileSync) {
                    SettingsRowTitle(.backupSettingsFile, "Sync settings file")
                    Text(BackupActions.settingsFilePath)
                }
                if core.settings.settingsFileEnabled {
                    LabeledContent {
                        Button("Show in Finder", action: BackupActions.revealSettingsFile)
                    } label: {
                        Text("Settings changed here are written to the file, and edits to it apply here.")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                SettingsSectionHeader(.backupSettingsFile)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.backup)
        .onDisappear {
            preparingBackup?.cancel()
            preparingBackup = nil
            if !importingBackup { discardPreview() }
        }
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
                "Unset matching Raycast shortcuts to avoid conflicts.",
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
            return String(localized: "A .tinycast file exported from Tinycast.")
        }
        if preparingBackup != nil { return name }
        return preview == nil ? String(localized: "\(name) — couldn't be read") : name
    }

    private func available(in manifest: BackupManifest) -> [BackupCategory: Int] {
        Dictionary(
            uniqueKeysWithValues: BackupCategory.ordered(manifest.categories).map {
                ($0, manifest.count($0))
            })
    }

    private func runExport() {
        guard !exporting,
            let destination = BackupActions.chooseSaveLocation(named: "Tinycast", type: .tinycastBackup)
        else { return }
        exporting = true
        backupStatus = nil
        let categories = exportSelection
        Task {
            defer { exporting = false }
            do {
                let message = try await mainApp.runBackup(.export(destination, categories))
                backupStatus = .success(message)
            } catch is CancellationError {
            } catch {
                backupStatus = .failure(error.localizedDescription)
            }
        }
    }

    private func chooseBackupFile() {
        guard let url = BackupActions.chooseBackupFile() else { return }
        discardPreview()
        backupFile = url
        backupStatus = nil
        preparingBackup = Task {
            defer { if !Task.isCancelled { preparingBackup = nil } }
            do {
                let prepared = try await mainApp.prepareBackup(at: url)
                preview = prepared
                importSelection = prepared.manifest.categories
            } catch is CancellationError {
            } catch {
                backupStatus = .failure(error.localizedDescription)
            }
        }
    }

    private func runBackupImport() {
        guard let preview, !importingBackup, !importSelection.isEmpty else { return }
        importingBackup = true
        let categories = importSelection
        Task {
            defer {
                discardPreview()
                backupFile = nil
                importingBackup = false
            }
            if categories.contains(.configuration) {
                guard
                    await BackupActions.confirmExecutableImport(
                        core: core, commands: preview.customCommands, shortcuts: preview.globalShortcuts)
                else { return }
            }
            do {
                let message = try await mainApp.runBackup(.apply(preview.id, categories))
                backupStatus = .success(message)
            } catch is CancellationError {
            } catch {
                backupStatus = .failure(error.localizedDescription)
            }
        }
    }

    private func discardPreview() {
        if let preview { mainApp.send(.discardBackup(preview.id)) }
        preview = nil
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
                let message = try await mainApp.runBackup(
                    .importRaycast(file, passphrase: passphrase, options: selection))
                status = .success(message)
                passphrase = ""
            } catch is CancellationError {
            } catch {
                status = .failure(error.localizedDescription)
            }
        }
    }
}
