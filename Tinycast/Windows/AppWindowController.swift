import AppKit
import SwiftUI

/// Built on first show, torn down on close so its SwiftUI tree deallocates. Never quits the app.
@MainActor
final class AppWindowController: NSObject, NSWindowDelegate {
    private let title: String
    private let contentSize: CGSize
    private let isResizable: Bool
    private let autosaveName: String?
    private let activation: ActivationPolicy
    private var window: NSWindow?
    /// Rebuilt with the window, so a chrome's state never outlives the window it decorated.
    private var chrome: WindowChrome?

    init(
        title: String, contentSize: CGSize, resizable: Bool = false, autosaveName: String? = nil,
        activation: ActivationPolicy
    ) {
        self.title = title
        self.contentSize = contentSize
        self.isResizable = resizable
        self.autosaveName = autosaveName
        self.activation = activation
    }

    /// Returns `true` when a window was built, `false` when an already-open one was re-raised.
    @discardableResult
    func show<Content: View>(
        chrome: WindowChrome? = nil, @ViewBuilder content: () -> Content
    ) -> Bool {
        let root = content()
        return show(chrome: chrome) {
            let hosting = NSHostingController(rootView: root)
            // Keep the window's size authoritative: an unconstrained fill would drive the frame.
            hosting.sizingOptions = []
            return hosting
        }
    }

    /// AppKit-built content; Settings needs it for a real `NSSplitViewController`.
    @discardableResult
    func show(chrome: WindowChrome? = nil, contentViewController: () -> NSViewController) -> Bool {
        if let window {
            raise(window)
            return false
        }
        let window = makeWindow(content: contentViewController())
        // After the content so the inset lands on a mounted view; before `raise` to avoid a flash.
        self.chrome = chrome
        chrome?.install(in: window)
        self.window = window
        activation.windowDidOpen(window)
        raise(window)
        return true
    }

    /// Re-raise an open window without rebuilding it; `false` when none is open.
    @discardableResult
    func focus() -> Bool {
        guard let window else { return false }
        raise(window)
        return true
    }

    func close() {
        window?.close()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let window else { return }
        self.window = nil
        self.chrome = nil
        activation.windowDidClose(window)
    }

    // MARK: - Private

    private func makeWindow(content: NSViewController) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        if isResizable { style.insert(.resizable) }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.title = title
        // Edge-to-edge under a transparent titlebar, so it reads as one surface.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        // AppKit would otherwise resurrect the window at launch, before anything is wired up.
        window.isRestorable = false
        window.contentMinSize = contentSize
        window.delegate = self

        window.contentViewController = content
        // `contentViewController` resets the frame to the controller's fitting size.
        window.setContentSize(contentSize)

        if let autosaveName {
            window.setFrameAutosaveName(autosaveName)
            if !window.setFrameUsingName(autosaveName) { window.center() }
        } else {
            window.center()
        }
        return window
    }

    private func raise(_ window: NSWindow) {
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // `NSApp.activate` is async, so re-assert next turn — never onto a window closed since.
        DispatchQueue.main.async { [weak self, weak window] in
            guard let window, self?.window === window else { return }
            window.makeKeyAndOrderFront(nil)
        }
    }
}
