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
                    Button("Export…") { Task { await BackupActions.exportSettings(core: core) } }
                } label: {
                    Text("Export Settings")
                    Text("Save your shortcuts, custom commands, favorites, and preferences to JSON.")
                }
                LabeledContent {
                    Button("Import…") { Task { await BackupActions.importSettings(core: core) } }
                } label: {
                    Text("Import Settings")
                    Text("Restore from a Tinycast backup. Only values in the file are changed.")
                }
            } header: {
                Text("Tinycast")
            }

            Section {
                LabeledContent {
                    Button("Choose…") { chooseRaycastFile() }
                } label: {
                    Text("Raycast Export")
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
                Text("Import from Raycast")
            }
        }
        .formStyle(.grouped)
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
