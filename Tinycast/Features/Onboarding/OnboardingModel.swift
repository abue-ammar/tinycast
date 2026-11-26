import Foundation
import Observation

@MainActor
@Observable
final class OnboardingModel {
    enum Step: Int, CaseIterable {
        case welcome, accessibility, importData, ready
    }

    enum ImportStatus {
        case success(String)
        case failure(String)
    }

    var step: Step = .welcome {
        didSet { movesForward = step.rawValue > oldValue.rawValue }
    }

    @ObservationIgnored private(set) var movesForward = true
    let shortcut: OnboardingShortcutSession
    private(set) var file: URL?
    var passphrase = ""
    private(set) var importing = false
    private(set) var status: ImportStatus?
    var selection: RaycastImportOptions = .all
    private(set) var isRaycastExport = false

    init(shortcut: OnboardingShortcutSession) {
        self.shortcut = shortcut
    }

    var canImport: Bool {
        isRaycastExport && !passphrase.isEmpty && !selection.isEmpty && !importing
    }

    var didImport: Bool {
        if case .success = status { return true }
        return false
    }

    func chooseFile() {
        guard let url = BackupActions.pickRaycastFile() else { return }
        selectFile(url)
    }

    func selectFile(_ url: URL?) {
        guard !importing, url?.isFileURL ?? true else { return }
        if file != url { passphrase = "" }
        file = url
        isRaycastExport = url.map(BackupActions.isRaycastExport) ?? false
        if url == nil { selection = .all }
        status = nil
    }

    func run(core: AppCore) {
        guard canImport, let file else { return }
        importing = true
        status = nil
        Task {
            defer { importing = false }
            do {
                let outcome = try await BackupActions.importRaycast(
                    core: core, file: file, passphrase: passphrase, options: selection)
                status = .success(BackupActions.raycastText(outcome))
                passphrase = ""
            } catch {
                status = .failure(error.localizedDescription)
            }
        }
    }
}
