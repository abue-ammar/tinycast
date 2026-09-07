import AppKit

@MainActor
final class ExtensionMenuBarController: NSObject, NSMenuDelegate {
    let entryID: String
    private(set) var isOpen = false
    var onOpen: (() -> Void)?
    var onClose: (() -> Void)?
    var onAction: ((String, String, String) -> Void)?
    var onActionUnavailable: (() -> Void)?
    private let status: NSStatusItem
    let menu = NSMenu()
    private let assetsPath: String
    private let loadImage: (RenderValue?, String, CGFloat) async -> NSImage?
    private var snapshot: ExtensionMenuBarSnapshot?
    private var iconTask: Task<Void, Never>?
    private var menuImageTask: Task<Void, Never>?
    private var deferredSnapshot: ExtensionMenuBarSnapshot?
    private var hasPreparedContent = false
    private var images: [(value: RenderValue, image: NSImage)] = []
    private var imageBindings: [(item: NSMenuItem, value: RenderValue)] = []
    private var failedIcons: [RenderValue] = []
    private let placeholder = NSImage(size: NSSize(width: 14, height: 14))
    private var iconFailed = false
    private var menuSession: String?
    private var pendingActions: [(identity: ItemIdentity, type: String)] = []
    private var identities: [ObjectIdentifier: ItemIdentity] = [:]

    private struct Action: Equatable {
        let session: String
        let handler: String
    }

    private struct ItemIdentity: Equatable {
        let path: [PathComponent]
        let key: String
        let modifiers: NSEvent.ModifierFlags
        let isAlternate: Bool
    }

    private enum PathComponent: Equatable {
        case item(String), section(String), submenu(String)
        case primary(String, String)
    }

    init(entryID: String, assetsPath: String, isVisible: Bool = true,
         loadImage: @escaping (RenderValue?, String, CGFloat) async -> NSImage? = {
             await ExtensionMenuBarImage.loadAdaptive($0, assetsPath: $1, size: $2)
         }) {
        self.entryID = entryID
        self.assetsPath = assetsPath
        self.loadImage = loadImage
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        status.autosaveName = entryID
        status.isVisible = isVisible
        status.button?.target = self
        status.button?.action = #selector(toggleMenu)
        status.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
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
        let iconChanged = previous?.iconJSON != snapshot.iconJSON || previous == nil
        if iconChanged { loadIcon() }
    }

    private func loadIcon() {
        iconTask?.cancel()
        guard let snapshot else { return }
        let assetsPath = self.assetsPath
        let loadImage = self.loadImage
        iconTask = Task { [weak self] in
            let image = await loadImage(snapshot.icon, assetsPath, 18)
            guard !Task.isCancelled, let self else { return }
            self.iconTask = nil
            self.iconFailed = snapshot.icon != nil && image == nil
            self.status.button?.image = image
                ?? ((snapshot.title ?? "").isEmpty
                    ? NSImage(systemSymbolName: "puzzlepiece.extension", accessibilityDescription: nil) : nil)
        }
    }

    func showMenu(_ root: RenderNode, session: String) {
        if menuSession != session {
            clearActions(in: menu)
            menuSession = session
            menuImageTask?.cancel()
            menuImageTask = nil
            failedIcons.removeAll()
            if iconFailed, iconTask == nil { loadIcon() }
        }
        if root.bool("isLoading") != true || !hasPreparedContent { apply(root.children, session: session) }
        if root.bool("isLoading") != true { dispatchPendingActions() }
        loadMenuImages()
    }

    private var nextIcon: RenderValue? {
        imageBindings.first { binding in
            !failedIcons.contains(binding.value) && !images.contains { $0.value == binding.value }
        }?.value
    }

    private func loadMenuImages() {
        guard menuImageTask == nil, nextIcon != nil else { return }
        let assetsPath = self.assetsPath
        let loadImage = self.loadImage
        menuImageTask = Task { [weak self] in
            while let value = self?.nextIcon {
                let image = await loadImage(value, assetsPath, 14)
                guard !Task.isCancelled, let self else { return }
                guard let image else { self.failedIcons.append(value); continue }
                guard self.imageBindings.contains(where: { $0.value == value }) else { continue }
                self.images.append((value, image))
                for binding in self.imageBindings where binding.value == value {
                    if binding.item.image !== image { binding.item.image = image }
                }
            }
            self?.menuImageTask = nil
        }
    }

    private func apply(_ nodes: [RenderNode], session: String?) {
        if isOpen, menu.size.width > menu.minimumWidth { menu.minimumWidth = menu.size.width }
        imageBindings.removeAll(keepingCapacity: true)
        identities.removeAll(keepingCapacity: true)
        reconcile(nodes, in: menu, session: session, path: [])
        images.removeAll { cached in !imageBindings.contains { $0.value == cached.value } }
        hasPreparedContent = !nodes.isEmpty
    }

    func showError(_ message: String) {
        pendingActions.removeAll()
        status.button?.toolTip = message
        guard !hasPreparedContent else { return }
        menuImageTask?.cancel()
        menuImageTask = nil
        apply([RenderNode(id: -1, type: "MenuBarExtra.Item", props: [
            "title": .string("Could not refresh"), "tooltip": .string(message)
        ])], session: nil)
    }

    private func reconcile(_ nodes: [RenderNode], in menu: NSMenu, session: String?, path: [PathComponent]) {
        var entries: [(node: RenderNode, role: String, parent: RenderNode?, path: [PathComponent])] = []
        func flatten(_ nodes: [RenderNode], path: [PathComponent]) {
            for node in nodes {
                switch node.type {
                case "MenuBarExtra.Section":
                    if !entries.isEmpty, entries.last?.role != "separator" {
                        entries.append((node, "separator", nil, path))
                    }
                    if let title = node.string("title"), !title.isEmpty { entries.append((node, "header", nil, path)) }
                    flatten(node.children, path: path + [.section(node.string("title") ?? "")])
                case "MenuBarExtra.Separator": entries.append((node, "separator", nil, path))
                case "MenuBarExtra.Item", "MenuBarExtra.Submenu":
                    entries.append((node, "item", nil, path))
                    if let alternate = node.node("alternate") {
                        let primary = PathComponent.primary(node.string("title") ?? "", node.string("subtitle") ?? "")
                        entries.append((alternate, "item", node, path + [primary]))
                    }
                default: break
                }
            }
        }
        flatten(nodes, path: path)
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
            if entry.role != "separator" {
                update(item, from: entry.node, session: session, parent: entry.parent, path: entry.path)
            }
            if menu.index(of: item) != index {
                if item.menu === menu { menu.removeItem(item) }
                menu.insertItem(item, at: index)
            }
        }
        while menu.numberOfItems > entries.count { menu.removeItem(at: menu.numberOfItems - 1) }
    }

    private func update(_ item: NSMenuItem, from node: RenderNode, session: String?, parent: RenderNode?, path: [PathComponent]) {
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
        let image = node.props["icon"].map { icon in
            imageBindings.append((item, icon))
            return images.first { $0.value == icon }?.image ?? placeholder
        }
        if item.image !== image { item.image = image }
        var enabled = handler != nil
        if node.type == "MenuBarExtra.Submenu", !node.children.isEmpty {
            let submenu = item.submenu ?? NSMenu()
            submenu.autoenablesItems = false
            reconcile(node.children, in: submenu, session: session, path: path + [.submenu(item.title)])
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
        if handler != nil {
            identities[ObjectIdentifier(item)] = ItemIdentity(path: path + [.item(item.title)], key: key,
                                                            modifiers: modifiers, isAlternate: parent != nil)
        }
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
        let event = NSApp.currentEvent
        let type = event?.type == .rightMouseUp || event?.type == .rightMouseDown ? "right-click" : "left-click"
        if let action = item.representedObject as? Action {
            onAction?(action.session, action.handler, type)
        } else {
            guard let identity = identities[ObjectIdentifier(item)],
                actionItems(in: menu).filter({ identities[ObjectIdentifier($0)] == identity }).count == 1 else {
                onActionUnavailable?()
                return
            }
            pendingActions.append((identity, type))
            onOpen?()
        }
    }

    private func actionItems(in menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { item in
            if let submenu = item.submenu { return actionItems(in: submenu) }
            return item.action == #selector(performAction(_:)) ? [item] : []
        }
    }

    private func dispatchPendingActions() {
        guard !pendingActions.isEmpty else { return }
        let pending = pendingActions
        pendingActions.removeAll()
        let items = actionItems(in: menu)
        var unavailable = false
        for request in pending {
            let matches = items.filter { identities[ObjectIdentifier($0)] == request.identity }
            if matches.count == 1, let action = matches.first?.representedObject as? Action {
                onAction?(action.session, action.handler, request.type)
            } else { unavailable = true }
        }
        if unavailable { onActionUnavailable?() }
    }

    @objc private func toggleMenu() {
        if isOpen { menu.cancelTracking(); return }
        guard snapshot?.hasMenu == true, let button = status.button else { return }
        button.highlight(true)
        defer { button.highlight(false) }
        let bounds = button.bounds
        let bottom = button.isFlipped ? bounds.maxY : bounds.minY
        menu.popUp(positioning: nil, at: NSPoint(x: bounds.minX, y: bottom), in: button)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu.items.isEmpty {
            let loading = NSMenuItem(title: "Loading…", action: nil, keyEquivalent: "")
            loading.isEnabled = false
            menu.addItem(loading)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        isOpen = true
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
        pendingActions.removeAll()
        clearActions(in: menu)
    }

    private func clearActions(in menu: NSMenu) {
        for item in menu.items {
            item.representedObject = nil
            if let submenu = item.submenu { clearActions(in: submenu) }
        }
    }

    func remove() {
        onOpen = nil
        onClose = nil
        onAction = nil
        onActionUnavailable = nil
        pendingActions.removeAll()
        menu.cancelTracking()
        menu.delegate = nil
        iconTask?.cancel()
        menuImageTask?.cancel()
        NSStatusBar.system.removeStatusItem(status)
    }
}
