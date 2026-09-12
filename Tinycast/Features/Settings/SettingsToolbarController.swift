import AppKit

/// AppKit, not SwiftUI's `.toolbar`: that only reaches a window owned by a SwiftUI `Scene`.
@MainActor
final class SettingsToolbarController: NSObject, WindowChrome, NSToolbarDelegate {
    private static let back = NSToolbarItem.Identifier("SettingsBack")
    private static let forward = NSToolbarItem.Identifier("SettingsForward")

    private let navigation: SettingsNavigationState
    private weak var window: NSWindow?
    private let backButton: NSButton
    private let forwardButton: NSButton

    init(navigation: SettingsNavigationState) {
        self.navigation = navigation
        // Two buttons, not a segmented control: that would draw a divider down the middle.
        backButton = Self.makeButton("chevron.backward", "Back")
        forwardButton = Self.makeButton("chevron.forward", "Forward")
        super.init()
        backButton.target = self
        backButton.action = #selector(goBack)
        forwardButton.target = self
        forwardButton.action = #selector(goForward)
    }

    // MARK: - WindowChrome

    func install(in window: NSWindow) {
        self.window = window
        // All three together are what puts the title inline and leading rather than centred.
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        // `.automatic` draws a hairline once content scrolls under the bar, splitting the surface.
        window.titlebarSeparatorStyle = .none
        // Transparent opts the titlebar out of the system's glass band; Settings wants it drawn.
        window.titlebarAppearsTransparent = false
        // Stock Settings isn't dragged by its content — a drag on a `Form` shouldn't move the window.
        window.isMovableByWindowBackground = false

        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.delegate = self
        // Labels would print "Back"/"Forward" under the chevrons and double the bar's height.
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        // Both, or a right-click still offers the display-mode items.
        toolbar.allowsDisplayModeCustomization = false
        window.toolbar = toolbar

        observe()
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // Everything after the tracking separator belongs to the detail column.
        [.sidebarTrackingSeparator, Self.back, Self.forward]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        switch identifier {
        case Self.back:
            item.view = backButton
            item.label = "Back"
        case Self.forward:
            item.view = forwardButton
            item.label = "Forward"
        default:
            return nil
        }
        // The one flag that seats an item ahead of the inline title rather than after it.
        item.isNavigational = true
        item.visibilityPriority = .high
        // The buttons take their enabled state from the history, not from responder validation.
        item.autovalidates = false
        return item
    }

    // MARK: - Private

    @objc private func goBack() { navigation.goBack() }
    @objc private func goForward() { navigation.goForward() }

    /// Re-armed after every read; the hop is because `onChange` fires before the write lands.
    private func observe() {
        withObservationTracking {
            sync()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func sync() {
        window?.title = navigation.tab.title
        backButton.isEnabled = navigation.canGoBack
        forwardButton.isEnabled = navigation.canGoForward
    }

    /// The directional pair, not `chevron.left/right`, so the control mirrors in RTL.
    private static func makeButton(_ symbol: String, _ label: String) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        let button = NSButton(image: image ?? NSImage(), target: nil, action: nil)
        button.bezelStyle = .toolbar
        button.setAccessibilityLabel(label)
        button.toolTip = label
        return button
    }
}
