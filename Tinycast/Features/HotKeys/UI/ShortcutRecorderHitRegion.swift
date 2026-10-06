import AppKit
import SwiftUI

struct ShortcutRecorderHitRegion: NSViewRepresentable {
    enum Region {
        case recorder, callout
    }

    let capture: ShortcutCaptureSession
    var region: Region = .recorder

    func makeNSView(context: Context) -> PassiveView {
        let view = PassiveView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: PassiveView, context: Context) {
        if view.capture !== capture || view.region != region { view.clearRegistration() }
        view.capture = capture
        view.region = region
        switch region {
        case .recorder: capture.setActiveRecorderView(view)
        case .callout: capture.setActiveCalloutView(view)
        }
    }

    static func dismantleNSView(_ view: PassiveView, coordinator: ()) {
        view.clearRegistration()
    }

    final class PassiveView: NSView {
        weak var capture: ShortcutCaptureSession?
        var region: Region = .recorder

        func clearRegistration() {
            switch region {
            case .recorder: capture?.clearActiveRecorderView(self)
            case .callout: capture?.clearActiveCalloutView(self)
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
