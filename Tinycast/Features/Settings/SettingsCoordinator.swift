import SwiftUI

/// Settings' lifecycle, independent of the palette: neither surface opens or closes the other.
@MainActor
final class SettingsCoordinator {
    private let window: AppWindowController
    /// Environment injection only — never for state this type owns.
    private unowned let core: AppCore
    /// The open window's session; the window's chrome and view tree own it, so this self-nils.
    private weak var navigation: SettingsNavigationState?
    /// The same session owns its transient editor stack; no panel survives the Settings window.
    private weak var editorPresenter: SettingsEditorPresenter?

    init(core: AppCore) {
        self.core = core
        window = AppWindowController(
            title: "Settings", contentSize: Theme.Size.settingsWindow, resizable: true,
            autosaveName: "SettingsWindow", activation: core.activationPolicy)
    }

    /// A fresh window mounts on `tab`; an open one navigates to it, recording the jump in history.
    /// A nil `tab` only reveals the window, so re-opening a minimised one keeps the pane it was on.
    func showSettings(tab: SettingsTab? = nil) {
        if window.focus() {
            if let tab { navigation?.select(tab) }
            return
        }
        let navigation = SettingsNavigationState(tab: tab ?? .general)
        let editorPresenter = SettingsEditorPresenter(core: core, navigation: navigation)
        self.navigation = navigation
        self.editorPresenter = editorPresenter
        var split: SettingsSplitViewController?
        window.show(chrome: SettingsToolbarController(navigation: navigation)) {
            let controller = SettingsSplitViewController(
                sidebar: inject(SettingsSidebarView(), navigation, editorPresenter),
                detail: inject(SettingsDetailView(), navigation, editorPresenter))
            split = controller
            return controller
        }
        editorPresenter.attach(to: split?.view.window)
    }

    /// Both columns are hosted separately, so each needs the whole environment.
    private func inject(
        _ view: some View, _ navigation: SettingsNavigationState,
        _ editorPresenter: SettingsEditorPresenter
    ) -> some View {
        view.settingsEnvironment(
            core: core, navigation: navigation, editorPresenter: editorPresenter)
    }

    func showAbout() {
        showSettings(tab: .about)
    }

    func showBackupSettings() {
        showSettings(tab: .backup)
    }

    /// ⌘Q and the window's close button land here; the app itself keeps running.
    func closeSettings() {
        editorPresenter?.dismissAll()
        window.close()
    }

    func focusExisting() -> Bool {
        window.focus()
    }
}
