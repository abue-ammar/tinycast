import Foundation

/// What the main app and Settings' own process share, and the work only the main app can run.
extension AppCore {
    func makeSharedStateMirror(send: @escaping (SharedChange) -> Void) -> SharedStateMirror {
        SharedStateMirror(
            domain: sharedDomain, reloadDefaults: { [weak self] in self?.reloadDefaultsStores() }, send: send)
    }

    /// Exhaustive, so a new domain fails to build until both roles know how to re-read it.
    private func sharedDomain(_ domain: SharedDomain) -> SharedStateMirror.Domain {
        switch domain {
        case .quicklinks:
            .init(
                observe: { [quicklinks] in _ = quicklinks.quicklinks },
                reload: { [quicklinks] in
                    quicklinks.load()
                    quicklinks.onChange?(quicklinks.quicklinks)
                })
        case .chatPresets:
            .init(
                observe: { [chatPresets] in _ = chatPresets.presets },
                reload: { [weak self] in self?.reloadChatPresets() })
        case .customQuickActions:
            .init(
                observe: { [customQuickActions] in _ = customQuickActions.actions },
                reload: { [customQuickActions] in
                    customQuickActions.load()
                    customQuickActions.onChange?(customQuickActions.actions)
                })
        case .launchAtLogin:
            .init(
                observe: { [settings] in _ = settings.launchAtLogin },
                reload: { [settings] in settings.reloadLaunchAtLogin() })
        case .launcherRanking:
            .init(
                observe: { [launcherRanking] in _ = launcherRanking.revision },
                reload: { [launcherRanking] in launcherRanking.reload() },
                settle: { [launcherRanking] in await launcherRanking.flush() })
        case .frequentEmoji:
            .init(
                observe: { [frequentEmoji] in _ = frequentEmoji.revision },
                reload: { [frequentEmoji] in frequentEmoji.reload() })
        case .calculatorHistory:
            .init(
                observe: { [calcHistory] in _ = calcHistory.entries },
                reload: { [calcHistory] in calcHistory.reload() })
        }
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
