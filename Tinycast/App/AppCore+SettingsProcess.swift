import Foundation

/// What the main app and Settings' own process share, and the work only the main app can run.
extension AppCore {
    func makeSharedStateMirror(send: @escaping (SharedChange) -> Void) -> SharedStateMirror {
        SharedStateMirror(
            domains: [
                .quicklinks: .init(
                    observe: { [quicklinks] in _ = quicklinks.quicklinks },
                    reload: { [quicklinks] in
                        quicklinks.load()
                        quicklinks.onChange?(quicklinks.quicklinks)
                    }),
                .chatPresets: .init(
                    observe: { [chatPresets] in _ = chatPresets.presets },
                    reload: { [weak self] in self?.reloadChatPresets() }),
                .customQuickActions: .init(
                    observe: { [customQuickActions] in _ = customQuickActions.actions },
                    reload: { [customQuickActions] in
                        customQuickActions.load()
                        customQuickActions.onChange?(customQuickActions.actions)
                    }),
                .launchAtLogin: .init(
                    observe: { [settings] in _ = settings.launchAtLogin },
                    reload: { [settings] in settings.reloadLaunchAtLogin() })
            ],
            reloadDefaults: { [weak self] in self?.reloadDefaultsStores() }, send: send)
    }

    /// Stores before shortcuts: whether a binding may register reads the stores' switches.
    private func reloadDefaultsStores() {
        settings.reload()
        aiSettings.reload()
        quickActionSettings.reload()
        mcpSettings.reload()
        aliases.reload()
        visibility.reload()
        favorites.reload()
        fallbacks.reload()
        customCommands.reload()
        windowLayouts.reload()
        customWindowSizes.reload()
        rooms.reload()
        calendarStore.reloadHiddenCalendars()
        hotKeys.reloadBindings()
    }

    /// Open chats follow a preset changed elsewhere, as they did when the pane ran here.
    private func reloadChatPresets() {
        let previous = chatPresets.presets
        chatPresets.load()
        for preset in previous where chatPresets.preset(id: preset.id) != preset {
            aiChats.followPreset(id: preset.id, to: chatPresets.preset(id: preset.id))
        }
    }
}
