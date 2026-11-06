import SwiftUI

struct GlassEffectView: NSViewRepresentable {
    /// Matches the surface's clip, so no square glass corner sits under it for a window animation.
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.cornerRadius = cornerRadius
        return view
    }

    func updateNSView(_ nsView: NSGlassEffectView, context: Context) {
        nsView.cornerRadius = cornerRadius
    }
}
