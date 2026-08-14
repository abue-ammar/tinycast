import AppKit
import SwiftUI

/// Draws an `NSImage` and plays it if it has more than one frame.
///
/// `Image(nsImage:)` renders a single frame and never advances, so an animated GIF reads as a still.
/// `NSImageView` owns the frame timer, which is the one piece SwiftUI has no equivalent for.
struct AnimatedImageView: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        // Neither axis may drive intrinsic size: a large GIF would otherwise widen the row it sits in.
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.image = image
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        guard view.image !== image else { return }
        view.image = image
        view.animates = true
    }
}

extension NSImage {
    /// True when a representation carries more than one frame — the only reason to pay for a timer.
    var isAnimated: Bool {
        representations.contains(where: { rep in
            guard let bitmap = rep as? NSBitmapImageRep,
                let frames = bitmap.value(forProperty: .frameCount) as? NSNumber
            else { return false }
            return frames.intValue > 1
        })
    }
}
