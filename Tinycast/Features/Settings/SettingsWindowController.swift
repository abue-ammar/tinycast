import SwiftUI

/// The Settings window itself; it lives in Settings' own process, whose lifetime it sets.
@MainActor
final class SettingsWindowController {
    private let window: AppWindowController
    /// Environment injection only — never for state this type owns.
    private unowned let core: AppCore
    /// The open window's session; the window's chrome and view tree own it, so this self-nils.
    private weak var navigation: SettingsNavigationState?
    /// The same session owns its transient editor stack; no panel survives the Settings window.
    private weak var editorPresenter: SettingsEditorPresenter?

    init(core: AppCore, onClose: @escaping () -> Void) {
        self.core = core
        window = AppWindowController(
            title: String(localized: "Settings"), contentSize: Theme.Size.settingsWindow, resizable: true,
            autosaveName: "SettingsWindow", activation: nil, onClose: onClose)
    }

    /// A fresh window mounts on the request's tab; an open one navigates to it, recording history.
    func show(_ request: SettingsRequest) {
        switch request.handoff {
        case .editWindowLayout(let edit): core.pendingWindowLayoutEdit = edit
        case .installFromStore(let install): core.pendingExtensionStoreInstall = install
        case nil: break
        }
        if window.focus() {
            if let tab = request.tab { navigation?.select(tab, revealing: request.target) }
            return
        }
        let navigation = SettingsNavigationState(tab: request.tab ?? .general)
        navigation.select(navigation.tab, revealing: request.target)
        let editorPresenter = SettingsEditorPresenter(core: core, navigation: navigation)
        self.navigation = navigation
        self.editorPresenter = editorPresenter
        let hosting = NSHostingController(
            rootView: SettingsRootView().settingsEnvironment(
                core: core, navigation: navigation, editorPresenter: editorPresenter))
        // Keep the window's size authoritative: an unconstrained fill would drive the frame.
        hosting.sizingOptions = []
        // The back/forward chevrons, the pane title and the sidebar's search field all ride on it.
        hosting.sceneBridgingOptions = [.toolbars, .title]
        window.show(chrome: SettingsWindowChrome()) { hosting }
        editorPresenter.attach(to: hosting.view.window)
    }

    func focus() -> Bool {
        window.focus()
    }

    /// ⌘Q and the window's close button land here; closing it ends Settings' process.
    func close() {
        editorPresenter?.dismissAll()
        window.close()
    }
}
