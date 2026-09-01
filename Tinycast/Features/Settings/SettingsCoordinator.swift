import SwiftUI

/// Settings' lifecycle, independent of the palette: neither surface opens or closes the other.
@MainActor
final class SettingsCoordinator {
    private let window: AppWindowController
    /// Environment injection only — never for state this type owns.
    private unowned let core: AppCore
    /// The open window's session; the window's chrome and view tree own it, so this self-nils.
    private weak var navigation: SettingsNavigationState?

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
        self.navigation = navigation
        window.show(chrome: SettingsToolbarController(navigation: navigation)) {
            SettingsSplitViewController(
                sidebar: inject(SettingsSidebarView(), navigation),
                detail: inject(SettingsDetailView(), navigation))
        }
    }

    /// Both columns are hosted separately, so each needs the whole environment.
    private func inject(_ view: some View, _ navigation: SettingsNavigationState) -> some View {
        view
            .environment(navigation)
            .environment(core)
            .environment(core.settings)
            .environment(core.appIndex)
            .environment(core.hotKeys)
            .environment(core.visibility)
            .environment(core.aliases)
            .environment(core.fallbacks)
            .environment(core.customCommands)
            .environment(core.snippetsStore)
            .environment(core.quicklinks)
            .environment(core.calendarStore)
            .environment(core.aiSettings)
            .environment(core.mcpSettings)
            .environment(core.quickActionSettings)
            .environment(core.chatGPTSubscription)
            // Propagates down so the window's materials show through, not each list's backing.
            .scrollContentBackground(.hidden)
    }

    func showAbout() {
        showSettings(tab: .about)
    }

    func showBackupSettings() {
        showSettings(tab: .backup)
    }

    /// ⌘Q and the window's close button land here; the app itself keeps running.
    func closeSettings() {
        window.close()
    }

    func focusExisting() -> Bool {
        window.focus()
    }
}
