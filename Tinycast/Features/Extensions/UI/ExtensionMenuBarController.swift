import AppKit

@MainActor
final class ExtensionMenuBarController: NSObject, NSMenuDelegate {
    let entryID: String
    private(set) var isOpen = false
    var onOpen: (() -> Void)?
    var onClose: (() -> Void)?
    var onAction: ((String, String, String) -> Void)?
    var onDisable: (() -> Void)?
    private let status: NSStatusItem
    let menu = NSMenu()
    private let assetsPath: String
    private var snapshot: ExtensionMenuBarSnapshot?
    private var iconTask: Task<Void, Never>?
    private var menuImageTask: Task<Void, Never>?

    private struct Action {
        let session: String
        let handler: String
    }

    init(entryID: String, assetsPath: String) {
        self.entryID = entryID
        self.assetsPath = assetsPath
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        status.autosaveName = entryID
        status.button?.imagePosition = .imageLeading
        menu.autoenablesItems = false
        menu.delegate = self

    }

    func update(_ snapshot: ExtensionMenuBarSnapshot) {
        let iconChanged = self.snapshot?.iconJSON != snapshot.iconJSON || self.snapshot == nil
        self.snapshot = snapshot
        status.button?.title = snapshot.title ?? ""
        status.button?.toolTip = snapshot.tooltip
        status.button?.setAccessibilityLabel(snapshot.tooltip ?? snapshot.title ?? "Extension menu")
        status.menu = snapshot.hasMenu ? menu : nil
        if iconChanged { loadIcon() }
    }

    private func loadIcon() {
        iconTask?.cancel()
        guard let snapshot else { return }
        let assetsPath = self.assetsPath
        iconTask = Task { [weak self] in
            let image = await ExtensionMenuBarImage.loadAdaptive(snapshot.icon, assetsPath: assetsPath)
            guard !Task.isCancelled, let self else { return }
            self.status.button?.image = image
                ?? ((snapshot.title ?? "").isEmpty
                    ? NSImage(systemSymbolName: "puzzlepiece.extension", accessibilityDescription: nil) : nil)
        }
    }

    func showMenu(_ root: RenderNode, session: String) {
        guard isOpen else { return }
        menuImageTask?.cancel()
        menu.removeAllItems()
        var images: [(NSMenuItem, RenderValue)] = []
        append(root.children, to: menu, session: session, images: &images)
        appendDisableItem()
        let assetsPath = self.assetsPath
        let isDark = status.button?.effectiveAppearance.isDark ?? false
        menuImageTask = Task {
            for (item, value) in images {
                guard !Task.isCancelled else { return }
                let image = await ExtensionMenuBarImage.load(value, assetsPath: assetsPath, isDark: isDark)
                guard !Task.isCancelled else { return }
                item.image = image
            }
        }
    }

    func showError(_ message: String) {
        status.button?.toolTip = message
        guard isOpen else { return }
        menuImageTask?.cancel()
        menu.removeAllItems()
        let item = NSMenuItem(title: "Could not refresh", action: nil, keyEquivalent: "")
        item.subtitle = message
        item.isEnabled = false
        menu.addItem(item)
        appendDisableItem()
    }

    private func append(_ nodes: [RenderNode], to menu: NSMenu, session: String,
                        images: inout [(NSMenuItem, RenderValue)]) {
        for node in nodes {
            switch node.type {
            case "MenuBarExtra.Section":
                if !menu.items.isEmpty, menu.items.last?.isSeparatorItem == false { menu.addItem(.separator()) }
                if let title = node.string("title"), !title.isEmpty { menu.addItem(.sectionHeader(title: title)) }
                append(node.children, to: menu, session: session, images: &images)
            case "MenuBarExtra.Separator":
                menu.addItem(.separator())
            case "MenuBarExtra.Item", "MenuBarExtra.Submenu":
                let item = makeItem(node, session: session, images: &images)
                if node.type == "MenuBarExtra.Submenu", !node.children.isEmpty {
                    let submenu = NSMenu()
                    submenu.autoenablesItems = false
                    append(node.children, to: submenu, session: session, images: &images)
                    item.submenu = submenu
                    item.isEnabled = !submenu.items.isEmpty
                }
                menu.addItem(item)
                if let alternate = node.node("alternate") {
                    item.keyEquivalentModifierMask.remove(.option)
                    let alternateItem = makeItem(alternate, session: session, images: &images)
                    alternateItem.isAlternate = true
                    alternateItem.keyEquivalent = item.keyEquivalent
                    alternateItem.keyEquivalentModifierMask = item.keyEquivalentModifierMask.union(.option)
                    menu.addItem(alternateItem)
                }
            default:
                break
            }
        }
    }

    private func makeItem(_ node: RenderNode, session: String, images: inout [(NSMenuItem, RenderValue)]) -> NSMenuItem {
        let item = NSMenuItem(title: node.string("title") ?? "", action: nil, keyEquivalent: "")
        item.subtitle = node.string("subtitle")
        item.toolTip = node.string("tooltip")
        item.isEnabled = false
        if let handler = node.handler("onAction") {
            item.target = self
            item.action = #selector(performAction(_:))
            item.representedObject = Action(session: session, handler: handler)
            item.isEnabled = true
        }
        if let icon = node.props["icon"] { images.append((item, icon)) }
        let rawShortcut = node.object("shortcut") ?? [:]
        let shortcut = rawShortcut["macOS"]?.objectValue ?? rawShortcut
        item.keyEquivalent = keyEquivalent(shortcut["key"]?.stringValue ?? "")
        item.keyEquivalentModifierMask = (shortcut["modifiers"]?.arrayValue ?? []).reduce(into: []) { flags, value in
            switch value.stringValue {
            case "cmd": flags.insert(.command)
            case "ctrl": flags.insert(.control)
            case "alt", "opt": flags.insert(.option)
            case "shift": flags.insert(.shift)
            default: break
            }
        }
        return item
    }

    private func keyEquivalent(_ key: String) -> String {
        switch key {
        case "return": return "\r"
        case "tab": return "\t"
        case "space": return " "
        case "escape": return "\u{1b}"
        case "backspace": return "\u{8}"
        case "delete": return "\u{7f}"
        case "arrowUp": return "\u{f700}"
        case "arrowDown": return "\u{f701}"
        case "arrowLeft": return "\u{f702}"
        case "arrowRight": return "\u{f703}"
        default: return key.lowercased()
        }
    }

    @objc private func performAction(_ item: NSMenuItem) {
        guard let action = item.representedObject as? Action else { return }
        let event = NSApp.currentEvent
        let type = event?.type == .rightMouseUp || event?.type == .rightMouseDown ? "right-click" : "left-click"
        onAction?(action.session, action.handler, type)
    }

    private func appendDisableItem() {
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        let item = NSMenuItem(title: "Remove from Menu Bar", action: #selector(disable), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    @objc private func disable() { onDisable?() }

    func menuWillOpen(_ menu: NSMenu) {
        isOpen = true
        menu.removeAllItems()
        let loading = NSMenuItem(title: "Loading…", action: nil, keyEquivalent: "")
        loading.isEnabled = false
        menu.addItem(loading)
        appendDisableItem()
        onOpen?()
    }

    func menuDidClose(_ menu: NSMenu) {
        isOpen = false
        menuImageTask?.cancel()
        onClose?()
    }

    func clearMenu() {
        guard !isOpen else { return }
        menu.removeAllItems()
    }

    func remove() {
        onOpen = nil
        onClose = nil
        onAction = nil
        onDisable = nil
        menu.cancelTracking()
        menu.delegate = nil
        iconTask?.cancel()
        menuImageTask?.cancel()
        NSStatusBar.system.removeStatusItem(status)
    }
}
