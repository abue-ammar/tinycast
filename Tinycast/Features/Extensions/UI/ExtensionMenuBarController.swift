import AppKit

@MainActor
final class ExtensionMenuBarController: NSObject, NSMenuDelegate {
    let entryID: String
    private(set) var isOpen = false
    var onOpen: (() -> Void)?
    var onClose: (() -> Void)?
    var onAction: ((String, String, String) -> Void)?
    private let status: NSStatusItem
    let menu = NSMenu()
    private let assetsPath: String
    private var snapshot: ExtensionMenuBarSnapshot?
    private var iconTask: Task<Void, Never>?
    private var menuImageTask: Task<Void, Never>?
    private var deferredSnapshot: ExtensionMenuBarSnapshot?
    private var content: [RenderNode] = []
    private var images: [(value: RenderValue, image: NSImage?)] = []
    private var menuSession: String?

    private struct Action: Equatable {
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
        if isOpen { deferredSnapshot = snapshot; return }
        guard self.snapshot != snapshot else { return }
        let previous = self.snapshot
        self.snapshot = snapshot
        if previous?.title != snapshot.title { status.button?.title = snapshot.title ?? "" }
        if previous?.tooltip != snapshot.tooltip { status.button?.toolTip = snapshot.tooltip }
        status.button?.setAccessibilityLabel(snapshot.tooltip ?? snapshot.title ?? "Extension menu")
        if previous?.hasMenu != snapshot.hasMenu { status.menu = snapshot.hasMenu ? menu : nil }
        let iconChanged = previous?.iconJSON != snapshot.iconJSON || previous == nil
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
        if root.bool("isLoading") == true, !content.isEmpty { return }
        menuSession = session
        menuImageTask?.cancel()
        let nodes = root.children
        var values: [RenderValue] = []
        collectIcons(nodes, into: &values)
        if values.allSatisfy({ value in images.contains { $0.value == value } }) {
            apply(nodes, session: session)
            return
        }
        let cached = images
        let assetsPath = self.assetsPath
        menuImageTask = Task { [weak self] in
            var loaded: [(value: RenderValue, image: NSImage?)] = []
            for value in values {
                let image: NSImage?
                if let existing = cached.first(where: { $0.value == value }) { image = existing.image } else {
                    image = await ExtensionMenuBarImage.loadAdaptive(value, assetsPath: assetsPath, size: 14)
                }
                guard !Task.isCancelled else { return }
                loaded.append((value, image))
            }
            guard let self else { return }
            self.images = loaded
            self.apply(nodes, session: self.menuSession == session ? session : nil)
        }
    }

    private func collectIcons(_ nodes: [RenderNode], into values: inout [RenderValue]) {
        for node in nodes {
            if let icon = node.props["icon"], !values.contains(icon) { values.append(icon) }
            collectIcons(node.children, into: &values)
            if let alternate = node.node("alternate") { collectIcons([alternate], into: &values) }
        }
    }

    private func apply(_ nodes: [RenderNode], session: String?) {
        if isOpen, menu.size.width > menu.minimumWidth { menu.minimumWidth = menu.size.width }
        reconcile(nodes, in: menu, session: session)
        content = nodes
    }

    func showError(_ message: String) {
        status.button?.toolTip = message
        guard content.isEmpty else { return }
        menuImageTask?.cancel()
        apply([RenderNode(id: -1, type: "MenuBarExtra.Item", props: [
            "title": .string("Could not refresh"), "tooltip": .string(message)
        ])], session: nil)
    }

    private func reconcile(_ nodes: [RenderNode], in menu: NSMenu, session: String?) {
        var entries: [(node: RenderNode, role: String, parent: RenderNode?)] = []
        func flatten(_ nodes: [RenderNode]) {
            for node in nodes {
                switch node.type {
                case "MenuBarExtra.Section":
                    if !entries.isEmpty, entries.last?.role != "separator" {
                        entries.append((node, "separator", nil))
                    }
                    if let title = node.string("title"), !title.isEmpty { entries.append((node, "header", nil)) }
                    flatten(node.children)
                case "MenuBarExtra.Separator": entries.append((node, "separator", nil))
                case "MenuBarExtra.Item", "MenuBarExtra.Submenu":
                    entries.append((node, "item", nil))
                    if let alternate = node.node("alternate") { entries.append((alternate, "item", node)) }
                default: break
                }
            }
        }
        flatten(nodes)
        for (index, entry) in entries.enumerated() {
            let identifier = NSUserInterfaceItemIdentifier("\(entry.node.id)-\(entry.role)")
            let item = menu.items.first { $0.identifier == identifier } ?? {
                switch entry.role {
                case "separator": return NSMenuItem.separator()
                case "header": return NSMenuItem.sectionHeader(title: entry.node.string("title") ?? "")
                default: return NSMenuItem(title: "", action: nil, keyEquivalent: "")
                }
            }()
            if item.identifier != identifier { item.identifier = identifier }
            if entry.role != "separator" { update(item, from: entry.node, session: session, parent: entry.parent) }
            if menu.index(of: item) != index {
                if item.menu === menu { menu.removeItem(item) }
                menu.insertItem(item, at: index)
            }
        }
        while menu.numberOfItems > entries.count { menu.removeItem(at: menu.numberOfItems - 1) }
    }

    private func update(_ item: NSMenuItem, from node: RenderNode, session: String?, parent: RenderNode?) {
        let title = node.string("title") ?? ""
        if item.isSectionHeader {
            if item.title != title { item.title = title }
        } else {
            let attributed = NSMutableAttributedString(string: title, attributes: [.foregroundColor: NSColor.labelColor])
            if let subtitle = node.string("subtitle"), !subtitle.isEmpty {
                attributed.append(NSAttributedString(string: " " + subtitle,
                                                       attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
            }
            if item.attributedTitle != attributed { item.attributedTitle = attributed }
        }
        if item.toolTip != node.string("tooltip") { item.toolTip = node.string("tooltip") }
        let handler = node.handler("onAction")
        if item.target !== self { item.target = self }
        let selector = handler == nil ? nil : #selector(performAction(_:))
        if item.action != selector { item.action = selector }
        let action = session.flatMap { session in handler.map { Action(session: session, handler: $0) } }
        if item.representedObject as? Action != action { item.representedObject = action }
        let image = node.props["icon"].flatMap { icon in images.first { $0.value == icon }?.image }
        if item.image !== image { item.image = image }
        var enabled = handler != nil
        if node.type == "MenuBarExtra.Submenu", !node.children.isEmpty {
            let submenu = item.submenu ?? NSMenu()
            submenu.autoenablesItems = false
            reconcile(node.children, in: submenu, session: session)
            if item.submenu !== submenu { item.submenu = submenu }
            enabled = !submenu.items.isEmpty
        } else if item.submenu != nil { item.submenu = nil }
        if item.isEnabled != enabled { item.isEnabled = enabled }
        let rawShortcut = (parent ?? node).object("shortcut") ?? [:]
        let shortcut = rawShortcut["macOS"]?.objectValue ?? rawShortcut
        let key = keyEquivalent(shortcut["key"]?.stringValue ?? "")
        if item.keyEquivalent != key { item.keyEquivalent = key }
        var modifiers = (shortcut["modifiers"]?.arrayValue ?? []).reduce(into: NSEvent.ModifierFlags()) { flags, value in
            switch value.stringValue {
            case "cmd": flags.insert(.command)
            case "ctrl": flags.insert(.control)
            case "alt", "opt": flags.insert(.option)
            case "shift": flags.insert(.shift)
            default: break
            }
        }
        if parent != nil { modifiers.insert(.option) } else if node.node("alternate") != nil { modifiers.remove(.option) }
        if item.keyEquivalentModifierMask != modifiers { item.keyEquivalentModifierMask = modifiers }
        if item.isAlternate != (parent != nil) { item.isAlternate = parent != nil }
    }

    private func keyEquivalent(_ key: String) -> String {
        switch key {
        case "return": return "\r"
        case "enter": return "\u{3}"
        case "tab": return "\t"
        case "space": return " "
        case "escape": return "\u{1b}"
        case "backspace": return "\u{8}"
        case "delete": return "\u{7f}"
        case "deleteForward": return "\u{f728}"
        case "home": return "\u{f729}"
        case "end": return "\u{f72b}"
        case "pageUp": return "\u{f72c}"
        case "pageDown": return "\u{f72d}"
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

    func menuWillOpen(_ menu: NSMenu) {
        isOpen = true
        if menu.items.isEmpty {
            let loading = NSMenuItem(title: "Loading…", action: nil, keyEquivalent: "")
            loading.isEnabled = false
            menu.addItem(loading)
        }
        onOpen?()
    }

    func menuDidClose(_ menu: NSMenu) {
        isOpen = false
        menu.minimumWidth = 0
        if let deferredSnapshot {
            self.deferredSnapshot = nil
            update(deferredSnapshot)
        }
        onClose?()
    }

    func clearMenu() {
        menuSession = nil
        func clearActions(_ menu: NSMenu) {
            for item in menu.items {
                item.representedObject = nil
                if let submenu = item.submenu { clearActions(submenu) }
            }
        }
        clearActions(menu)
    }

    func remove() {
        onOpen = nil
        onClose = nil
        onAction = nil
        menu.cancelTracking()
        menu.delegate = nil
        iconTask?.cancel()
        menuImageTask?.cancel()
        NSStatusBar.system.removeStatusItem(status)
    }
}
