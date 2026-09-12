import AppKit
import SwiftUI

/// Reports the `NSWindow` hosting a SwiftUI tree, for the AppKit surfaces that hang off its frame.
struct WindowReader: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // Nil until the view enters the hierarchy, and a palette never moves between windows.
        DispatchQueue.main.async { onResolve(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}
