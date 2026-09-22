import SwiftUI

/// The chat header's model, reasoning and staged-file menus, and the row each one opens on.
@MainActor
enum AIModelMenu {
    /// Every model configured for chat; selecting one updates the app-wide default route.
    static func models(coordinator: AIChatCoordinator) -> PopoverMenuContent {
        let groups = coordinator.modelGroups
        let loading = coordinator.isModelCatalogLoading
        var items = groups.flatMap { group in
            group.options.enumerated().map { index, option in
                PopoverMenuItem(
                    title: option.title, icon: option.menuIcon,
                    sectionTitle: index == 0 ? group.title : nil
                ) {
                    coordinator.selectModel(option)
                }
            }
        }
        if loading {
            items.insert(
                PopoverMenuItem(title: "Loading models…", icon: .blank, isLoading: true) {}, at: 0)
        }
        guard !items.isEmpty else {
            return PopoverMenuContent(items: [
                PopoverMenuItem(title: "Configure AI", systemImage: "slider.horizontal.3") {
                    coordinator.showSettings()
                }
            ])
        }
        return PopoverMenuContent(items: items)
    }

    static func reasoning(
        coordinator: AIChatCoordinator, settings: AISettingsStore
    ) -> PopoverMenuContent {
        let selected = settings.defaultModel?.effort
        return PopoverMenuContent(
            items: coordinator.reasoningEfforts.map { effort in
                PopoverMenuItem(
                    title: effort.title, icon: .blank,
                    detail: effort.id == selected ? "✓" : nil
                ) {
                    coordinator.selectReasoningEffort(effort)
                }
            })
    }

    /// One row per staged file, its ✕ beside the name: picking one takes that file back alone.
    static func attachments(
        chat: AIChatState, coordinator: AIChatCoordinator
    ) -> PopoverMenuContent {
        var items = chat.pendingAttachments.map { attachment in
            PopoverMenuItem(
                title: attachment.name, icon: .symbol(attachment.glyph), detail: "✕"
            ) {
                coordinator.removeAttachment(attachment.id)
            }
        }
        if items.count > 1 {
            items.append(
                PopoverMenuItem(
                    title: "Remove All", systemImage: "xmark.circle", startsSection: true
                ) {
                    coordinator.clearAttachments()
                })
        }
        return PopoverMenuContent(header: "Attached", items: items)
    }

    static func modelHighlight(coordinator: AIChatCoordinator, settings: AISettingsStore) -> Int {
        let options = coordinator.modelOptions
        // With nothing to choose yet, the loading row is the only row the menu has.
        guard !options.isEmpty else { return 0 }
        let offset = coordinator.isModelCatalogLoading ? 1 : 0
        let selectedIndex =
            settings.defaultModel.flatMap { selected in
                options.firstIndex(where: { $0.matches(selected) })
            } ?? 0
        return offset + selectedIndex
    }

    static func reasoningHighlight(coordinator: AIChatCoordinator, settings: AISettingsStore) -> Int {
        let selected = settings.defaultModel?.effort
        return coordinator.reasoningEfforts.firstIndex { $0.id == selected } ?? 0
    }
}
