import AppKit

@MainActor
final class FileSearchCoordinator {
    private let paletteCoordinator: PaletteCoordinator
    private unowned let core: AppCore

    init(paletteCoordinator: PaletteCoordinator, core: AppCore) {
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    func open(_ result: FileSearchResult) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        Task {
            do {
                _ = try await NSWorkspace.shared.open(
                    result.url, configuration: NSWorkspace.OpenConfiguration())
            } catch {
                await core.showNotice(
                    title: "Couldn’t Open \(result.name)",
                    message: error.localizedDescription,
                    symbol: result.isDirectory ? "folder" : "doc", tone: .danger)
            }
        }
    }

    func showInFinder(_ result: FileSearchResult) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(result.url)
    }

    func copyPath(_ result: FileSearchResult) {
        Paster.copyPlainText(result.id)
        core.showMessage("Copied path")
    }
}
