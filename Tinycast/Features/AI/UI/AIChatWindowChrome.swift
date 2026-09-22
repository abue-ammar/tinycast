import AppKit

/// The AI Chat window's toolbar, title and chords; it lives exactly as long as the window does.
@MainActor
final class AIChatWindowChrome: NSObject, WindowChrome, NSToolbarDelegate, NSSearchFieldDelegate {
    static let windowIdentifier = NSUserInterfaceItemIdentifier("AIChatWindow")
    private static let search = NSToolbarItem.Identifier("AIChatSearch")
    private static let actions = NSToolbarItem.Identifier("AIChatActions")
    private static let newChat = NSToolbarItem.Identifier("AIChatNewChat")

    private let coordinator: AIChatCoordinator
    private let chats: AIChatSurfacesState
    private let find: ChatFindState
    private weak var window: NSWindow?
    private var keyMonitor: Any?
    private let searchItem: NSSearchToolbarItem
    private let actionsButton: NSButton

    init(coordinator: AIChatCoordinator, chats: AIChatSurfacesState, find: ChatFindState) {
        self.coordinator = coordinator
        self.chats = chats
        self.find = find
        searchItem = NSSearchToolbarItem(itemIdentifier: Self.search)
        actionsButton = NSButton(
            image: NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Actions")
                ?? NSImage(),
            target: nil, action: nil)
        super.init()
        searchItem.searchField.placeholderString = "Find in Chat"
        searchItem.searchField.delegate = self
        searchItem.toolTip = "Find in Chat  ⌘F"
        searchItem.resignsFirstResponderWithCancel = true
        actionsButton.bezelStyle = .toolbar
        actionsButton.toolTip = "Actions  ⌘K"
        actionsButton.target = self
        actionsButton.action = #selector(showActions)
    }

    isolated deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    // MARK: - WindowChrome

    func install(in window: NSWindow) {
        self.window = window
        window.identifier = Self.windowIdentifier
        // Inline and leading, as Settings' is, so the title reads as the open chat's name.
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        // The system's own toolbar band, as every document window has: content scrolls beneath it.
        window.titlebarAppearsTransparent = false
        // Dragging across a transcript selects text; it must never move the window.
        window.isMovableByWindowBackground = false

        let toolbar = NSToolbar(identifier: "AIChatToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.allowsDisplayModeCustomization = false
        window.toolbar = toolbar

        installKeyMonitor()
        observeTitle()
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, Self.search, Self.actions,
            Self.newChat
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch identifier {
        case Self.search:
            return searchItem
        case Self.actions:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.view = actionsButton
            item.label = "Actions"
            return item
        case Self.newChat:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.image = NSImage(
                systemSymbolName: "square.and.pencil", accessibilityDescription: nil)
            item.label = "New Chat"
            item.toolTip = "New Chat  ⌘N"
            item.isBordered = true
            item.target = self
            item.action = #selector(newChat)
            return item
        default:
            return nil
        }
    }

    // MARK: - NSSearchFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        find.query = searchItem.searchField.stringValue
    }

    /// Return walks the matches, ⇧↩ walks back, as Find does in every Mac app.
    func control(
        _ control: NSControl, textView: NSTextView, doCommandBy selector: Selector
    ) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
        let backwards = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
        find.step(backwards ? -1 : 1, in: chats.window.session.messages)
        return true
    }

    func searchFieldDidEndSearching(_ sender: NSSearchField) {
        find.query = ""
    }

    // MARK: - Actions

    @objc private func newChat() { coordinator.newChat() }

    @objc private func showActions() {
        let menu = AIChatActionsMenu.build(
            chat: chats.window, coordinator: coordinator,
            findInChat: { [weak self] in self?.beginFind() })
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: actionsButton.bounds.maxY + Theme.Spacing.xs),
            in: actionsButton)
    }

    private func beginFind() {
        searchItem.beginSearchInteraction()
    }

    // MARK: - Private

    /// Re-armed after every read; the hop is because `onChange` fires before the write lands.
    private func observeTitle() {
        withObservationTracking {
            window?.title = coordinator.title(of: chats.window)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeTitle() }
        }
    }

    /// ⌘V, ⌘F, ⌘G and ⌘K have no menu item to hang on, so the window claims them before AppKit.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window, window.isKeyWindow,
                !event.isARepeat
            else { return event }
            return self.handle(event, in: window) ? nil : event
        }
    }

    private func handle(_ event: NSEvent, in window: NSWindow) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = (ASCIIKeyboardLayout.character(for: event) ?? event.charactersIgnoringModifiers)?
            .lowercased()
        switch (modifiers, key) {
        case ([.command], "f"):
            beginFind()
            return true
        case ([.command], "g"), ([.command, .shift], "g"):
            find.step(modifiers.contains(.shift) ? -1 : 1, in: chats.window.session.messages)
            return true
        case ([.command], "k"):
            showActions()
            return true
        case ([.command], "v"):
            // The search and rename fields take a paste as text, whatever the board holds.
            guard (window.firstResponder as? NSTextView)?.isFieldEditor != true else { return false }
            let files = PasteboardFiles.urls(on: .general)
            return coordinator.attachPastedFile(files: files, to: chats.window)
        default:
            return false
        }
    }
}

/// The window's ⌘K menu: Quick AI's actions, plus what only a saved chat in a window can do.
@MainActor
enum AIChatActionsMenu {
    static func build(
        chat: AIChatState, coordinator: AIChatCoordinator, findInChat: @escaping () -> Void
    ) -> NSMenu {
        let menu = NSMenu()
        let saved = coordinator.isSaved(chat)
        if chat.isStreaming {
            menu.addItem(
                ClosureMenuItem("Stop Response", symbol: "stop.fill") {
                    coordinator.stopResponse(in: chat)
                })
        }
        menu.addItem(
            ClosureMenuItem("New Chat", symbol: "square.and.pencil", key: "n") {
                coordinator.newChat()
            })
        if !chat.isStreaming, chat.session.messages.last?.role == .assistant {
            menu.addItem(
                ClosureMenuItem("Regenerate Response", symbol: "arrow.clockwise") {
                    coordinator.regenerate(in: chat)
                })
        }
        menu.addItem(.separator())
        if chat.lastAssistantText != nil {
            menu.addItem(
                ClosureMenuItem("Copy Last Response", symbol: "doc.on.doc") {
                    coordinator.copyLastResponse(in: chat)
                })
        }
        if saved {
            menu.addItem(
                ClosureMenuItem("Copy Chat", symbol: "text.bubble") {
                    coordinator.copyChat(id: chat.session.id)
                })
        }
        if !chat.pendingAttachments.isEmpty {
            menu.addItem(
                ClosureMenuItem("Remove Attachments", symbol: "paperclip") {
                    coordinator.clearAttachments(in: chat)
                })
        }
        if saved {
            menu.addItem(.separator())
            let pinned = coordinator.isPinned(chat)
            menu.addItem(
                ClosureMenuItem(pinned ? "Unpin Chat" : "Pin Chat", symbol: "pin") {
                    coordinator.togglePin(id: chat.session.id)
                })
            menu.addItem(
                ClosureMenuItem("Delete Chat…", symbol: "trash") {
                    Task { await coordinator.deleteChat(id: chat.session.id) }
                })
        }
        menu.addItem(.separator())
        menu.addItem(
            ClosureMenuItem("Find in Chat", symbol: "magnifyingglass", key: "f", findInChat))
        menu.addItem(
            ClosureMenuItem("AI Settings", symbol: "slider.horizontal.3") {
                coordinator.showSettings()
            })
        return menu
    }
}

/// An `NSMenuItem` that runs a closure, so a menu built per open needs no selector per row.
private final class ClosureMenuItem: NSMenuItem {
    private let run: () -> Void

    init(_ title: String, symbol: String, key: String = "", _ run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(runAction), keyEquivalent: key)
        target = self
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    @objc private func runAction() { run() }
}
