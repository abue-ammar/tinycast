import AppKit
import SwiftUI

@MainActor
final class PlanUsageMenuBarController: NSObject, NSMenuDelegate {
    private unowned let coordinator: PlanUsageCoordinator
    private let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private var isOpen = false
    private var isRemoved = false

    init(coordinator: PlanUsageCoordinator) {
        self.coordinator = coordinator
        super.init()
        status.autosaveName = "AIUsage"
        menu.delegate = self
        menu.autoenablesItems = false
        status.menu = menu
        observe()
    }

    func remove() {
        isRemoved = true
        menu.cancelTracking()
        NSStatusBar.system.removeStatusItem(status)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        isOpen = true
        coordinator.refresh()
    }

    func menuDidClose(_ menu: NSMenu) {
        isOpen = false
    }

    private func observe() {
        guard !isRemoved else { return }
        withObservationTracking {
            updateButton()
            if isOpen { rebuildMenu() }
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func updateButton() {
        guard let button = status.button else { return }
        let target = coordinator.target
        button.image = PlanUsageGauge.image(for: target)
        let label =
            target.map { target in
                let percent = PlanUsageFormat.percent(target.window.usedPercent, locale: .current)
                return String(
                    localized: "\(target.provider.title) \(target.window.title): \(percent) used")
            } ?? String(localized: "AI Usage")
        button.toolTip = label
        button.setAccessibilityLabel(label)
    }

    private func rebuildMenu() {
        let now = Date()
        menu.removeAllItems()
        let entries = PlanUsage.Provider.allCases.compactMap { provider in
            coordinator.monitor.entries[provider].map { (provider, $0) }
        }
        if entries.isEmpty { menu.addItem(emptyItem()) }
        for (index, (provider, entry)) in entries.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            menu.addItem(sectionItem(provider, entry: entry, now: now))
            if let credits = entry.usage?.resetCredits, credits > 0 {
                menu.addItem(resetItem(credits: credits))
            }
        }
        menu.addItem(.separator())
        if let pinItem = pinItem() { menu.addItem(pinItem) }
        menu.addItem(item(String(localized: "Refresh"), action: #selector(refresh)))
        menu.addItem(item(String(localized: "AI Settings…"), action: #selector(showSettings)))
    }

    private func sectionItem(
        _ provider: PlanUsage.Provider, entry: PlanUsageEntry, now: Date
    ) -> NSMenuItem {
        let host = NSHostingView(
            rootView: PlanUsageSection(provider: provider, entry: entry, now: now).motionScope())
        host.frame.size = host.fittingSize
        let item = NSMenuItem()
        item.view = host
        return item
    }

    private func emptyItem() -> NSMenuItem {
        if coordinator.isCheckingProviders {
            let item = item(String(localized: "Checking usage…"), action: nil)
            item.isEnabled = false
            return item
        }
        guard coordinator.availableProviders.isEmpty else {
            let item = item(String(localized: "No plan limits to show"), action: nil)
            item.isEnabled = false
            return item
        }
        return item(String(localized: "Turn On Claude or Codex…"), action: #selector(showProviders))
    }

    private func resetItem(credits: Int) -> NSMenuItem {
        let item = item(String(localized: "Reset ChatGPT Limits…"), action: #selector(useResetCredit))
        item.subtitle = String(localized: "\(credits) free resets available")
        return item
    }

    private func pinItem() -> NSMenuItem? {
        let usage = coordinator.monitor.usage
        let providers = PlanUsage.Provider.allCases.filter { usage[$0] != nil }
        guard providers.flatMap({ usage[$0]?.windows ?? [] }).count > 1 else { return nil }
        let pinned = coordinator.pin.effective(in: usage)
        let submenu = NSMenu()
        submenu.addItem(pinOption(String(localized: "Most Used"), pin: .automatic, pinned: pinned))
        for provider in providers {
            submenu.addItem(.separator())
            submenu.addItem(.sectionHeader(title: provider.title))
            for window in usage[provider]?.windows ?? [] {
                submenu.addItem(
                    pinOption(window.title, pin: .window(provider, id: window.id), pinned: pinned))
            }
        }
        let item = item(String(localized: "Show in Menu Bar"), action: nil)
        item.submenu = submenu
        return item
    }

    private func pinOption(_ title: String, pin: PlanUsagePin, pinned: PlanUsagePin) -> NSMenuItem {
        let option = item(title, action: #selector(choosePin(_:)))
        option.representedObject = pin.rawValue
        option.state = pin == pinned ? .on : .off
        return option
    }

    private func item(_ title: String, action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func refresh() {
        coordinator.refresh()
    }

    @objc private func showSettings() {
        coordinator.showSettings()
    }

    @objc private func showProviders() {
        coordinator.showProviders()
    }

    @objc private func useResetCredit() {
        coordinator.useResetCredit()
    }

    @objc private func choosePin(_ sender: NSMenuItem) {
        coordinator.setPin(PlanUsagePin(rawValue: sender.representedObject as? String))
    }
}
