import Foundation

/// Fills in a preset, asking first only when that replaces shortcuts the user set.
@MainActor
final class WindowShortcutPresetCoordinator {
    private let hotKeys: HotKeyManager
    /// Dialog and HUD presentation only. Never state this type owns.
    private unowned let core: AppCore

    init(hotKeys: HotKeyManager, core: AppCore) {
        self.hotKeys = hotKeys
        self.core = core
    }

    /// Read from the live bindings, so any edit that breaks the match clears it.
    var matchingPreset: WindowShortcutPreset? {
        WindowShortcutPreset.matching(currentBindings())
    }

    func apply(_ preset: WindowShortcutPreset) async {
        var current = currentBindings()
        var plan = WindowShortcutPresetPlan(preset: preset, current: current)
        guard !plan.assignments.isEmpty else {
            core.showMessage("\(preset.title) shortcuts already set")
            return
        }
        if !plan.overwritten.isEmpty {
            let confirmed = Set(plan.overwritten)
            guard
                await core.confirm(
                    title: plan.overwritten.count == 1
                        ? "Replace 1 shortcut?" : "Replace \(plan.overwritten.count) shortcuts?",
                    message: replacementMessage(plan.overwritten, preset: preset),
                    symbol: "keyboard", confirmTitle: "Replace")
            else { return }
            // A settings.json reload can rebind while the dialog waits; never replace an unseen key.
            current = currentBindings()
            plan = WindowShortcutPresetPlan(preset: preset, current: current)
            guard Set(plan.overwritten).isSubset(of: confirmed) else { return await apply(preset) }
        }
        // Cleared before any is set, so a key moving between two commands never blocks itself.
        for id in plan.displaced + plan.assignments.keys where current[id] != nil {
            hotKeys.setBinding(nil, for: .windowCommand(id: id))
        }
        var skipped: [WindowCommand.ID] = []
        for id in WindowCommand.ID.allCases {
            guard let binding = plan.assignments[id] else { continue }
            let action = HotKeyAction.windowCommand(id: id)
            guard hotKeys.conflictOwner(of: binding, excluding: action) == nil else {
                skipped.append(id)
                continue
            }
            hotKeys.setBinding(binding, for: action)
        }
        // The old binding returns when it is still free, so a clash never costs a working one.
        for id in skipped {
            let action = HotKeyAction.windowCommand(id: id)
            if let previous = current[id],
                hotKeys.conflictOwner(of: previous, excluding: action) == nil
            {
                hotKeys.setBinding(previous, for: action)
            }
        }
        if skipped.isEmpty {
            core.showMessage("Applied \(preset.title) shortcuts")
        } else {
            core.showMessage(
                "Applied \(preset.title) shortcuts — \(skipped.count) skipped, keys in use",
                tone: .danger)
        }
    }

    private func currentBindings() -> [WindowCommand.ID: HotKeyBinding] {
        var current: [WindowCommand.ID: HotKeyBinding] = [:]
        for id in WindowCommand.ID.allCases {
            current[id] = hotKeys.binding(for: .windowCommand(id: id))
        }
        return current
    }

    private func replacementMessage(
        _ ids: [WindowCommand.ID], preset: WindowShortcutPreset
    ) -> String {
        let names = ids.compactMap { WindowCommandCatalog.command(id: $0)?.name }
        let listed = names.prefix(3).joined(separator: ", ")
        let rest = names.count > 3 ? " and \(names.count - 3) more" : ""
        return "\(listed)\(rest) will use the \(preset.title) keys instead of the ones you set."
    }
}
