import AppKit

@MainActor
final class LanternDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 240),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "E2E Lantern"
        let title = NSTextField(labelWithString: "Lantern fixture ready")
        title.font = .systemFont(ofSize: 28, weight: .semibold)
        let detail = NSTextField(labelWithString: "Opened from Tinycast")
        detail.font = .systemFont(ofSize: 20)
        let stack = NSStackView(views: [title, detail])
        stack.orientation = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        if let content = window.contentView {
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: content.centerYAnchor)
            ])
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = LanternDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
