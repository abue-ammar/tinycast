import Foundation

/// Settings' lifecycle, independent of the palette: neither surface opens or closes the other.
@MainActor
final class SettingsCoordinator {
    /// The window lives in Settings' own process, so its memory leaves when it closes.
    private enum Surface {
        case window(SettingsWindowController)
        case process(SettingsProcessController)
    }

    private let surface: Surface

    init(core: AppCore) {
        switch ProcessRole.current {
        case .settings:
            surface = .window(
                SettingsWindowController(
                    core: core,
                    onClose: { [unowned core] in
                        core.mainApp?.beginClosing()
                        core.terminate()
                    }))
        case .main:
            surface = .process(SettingsProcessController(core: core))
        }
    }

    /// A nil `tab` only reveals the window, so re-opening a minimised one keeps the pane it was on.
    func showSettings(
        tab: SettingsTab? = nil, revealing target: SettingsTarget? = nil, handoff: SettingsHandoff? = nil
    ) {
        show(SettingsRequest(tab: tab, target: target, handoff: handoff))
    }

    func show(_ request: SettingsRequest) {
        switch surface {
        case .window(let window): window.show(request)
        case .process(let process): process.show(request)
        }
    }

    func showAbout() {
        showSettings(tab: .about)
    }

    func showBackupSettings() {
        showSettings(tab: .backup)
    }

    func focusExisting() -> Bool {
        switch surface {
        case .window(let window): window.focus()
        case .process(let process): process.focus()
        }
    }

    /// ⌘Q in Settings' own process; closing the window is what ends it.
    func closeSettings() {
        guard case .window(let window) = surface else { return }
        window.close()
    }
}
