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

    func body(content: Content) -> some View {
        content
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
        guard let window = event.window,
            // Only while something is actually being edited: the field editor is the responder.
            let editor = window.firstResponder as? NSTextView, editor.isFieldEditor
        else { return }
        let hit = window.contentView?.hitTest(event.locationInWindow)
        // A click on the field being edited, or on another text control, is that control's business.
        guard let hit, !hit.isDescendant(of: editor), !(hit is NSTextView) else { return }
        window.makeFirstResponder(nil)
    }
}

extension View {
    /// Drops keyboard focus when a click lands outside the field being edited.
    func releasesFocusOnOutsideClick() -> some View {
        modifier(FocusReleaseOnOutsideClick())
    }
}
