import AppKit
import SwiftUI

/// A field holds first responder until another claims it, and blank form space claims nothing.
private struct FocusReleaseOnOutsideClick: ViewModifier {
    @State private var monitor: Any?
    // A box, not `@State` on the window: resolving it must not invalidate the view mid-layout.
    @State private var host = HostWindowBox()

    func body(content: Content) -> some View {
        content
            .background(HostWindowReader { host.window = $0 })
            .onAppear {
                guard monitor == nil else { return }
                // A monitor, not a gesture: a gesture would swallow the click or steal focus.
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
                    release(on: event)
                    return event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }

    private func release(on event: NSEvent) {
        // A local monitor sees every window in the app; only this pane's own is ours to touch.
        guard let window = event.window, window === host.window,
            // Only while something is actually being edited: the field editor is the responder.
            let editor = window.firstResponder as? NSTextView, editor.isFieldEditor
        else { return }
        let hit = window.contentView?.hitTest(event.locationInWindow)
        // A click on the edited field, or another text control, is that control's business.
        guard let hit, !hit.isDescendant(of: editor), !(hit is NSTextView) else { return }
        window.makeFirstResponder(nil)
    }
}

private final class HostWindowBox {
    weak var window: NSWindow?
}

/// The window a SwiftUI view landed in; `NSViewRepresentable` is the only route to it.
private struct HostWindowReader: NSViewRepresentable {
    var onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView { HostWindowReaderView(onResolve: onResolve) }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class HostWindowReaderView: NSView {
    private let onResolve: (NSWindow?) -> Void

    init(onResolve: @escaping (NSWindow?) -> Void) {
        self.onResolve = onResolve
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onResolve(window)
    }
}

extension View {
    /// Drops keyboard focus when a click lands outside the field being edited, in this window only.
    func releasesFocusOnOutsideClick() -> some View {
        modifier(FocusReleaseOnOutsideClick())
    }
}
