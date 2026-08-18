import AppKit
import SwiftUI

/// Clicking away from a text field leaves it focused: a SwiftUI text field on macOS holds first
/// responder until another focusable view claims it, and blank form space claims nothing. So the
/// window is watched for clicks that land outside the open field editor, and focus is dropped there.
///
/// A local event monitor rather than a gesture: a gesture over the form would either swallow the
/// click or fire alongside the one that is focusing a *different* field, and take its focus away.
private struct FocusReleaseOnOutsideClick: ViewModifier {
    @State private var monitor: Any?
    // A box, not `@State` on the window: resolving it must not invalidate the view mid-layout.
    @State private var host = HostWindowBox()

    func body(content: Content) -> some View {
        content
            .background(HostWindowReader { host.window = $0 })
            .onAppear {
                guard monitor == nil else { return }
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
        // A click on the field being edited, or on another text control, is that control's business.
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
