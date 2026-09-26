import AppKit
import SwiftUI

enum Theme {
    enum Duration {
        static let enter: TimeInterval = 0
        static let exit: TimeInterval = 0
    }
}

@MainActor
final class HUDPanel: NSPanel {
    private var showing = false
    override var isVisible: Bool { showing }
    init(acceptsMouseEvents: Bool) {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        isReleasedWhenClosed = false
    }
    func cancelFade() {}
    override func orderFrontRegardless() { showing = true }
    func fadeIn(duration: TimeInterval, order: () -> Void) { order() }
    func fadeOut(duration: TimeInterval) { showing = false }
}

@main
@MainActor
struct MonitorHUDTests {
    static func main() async {
        _ = NSApplication.shared
        let presenter = HUDPresenter(anchor: .heightFraction(0.12), dwell: 0.1, screen: { nil })
        presenter.show(Text("50%"), size: CGSize(width: 100, height: 100), dwells: false)
        try? await Task.sleep(for: .milliseconds(250))
        assert(presenter.isShowing, "Pending hardware must not start a dismissal timer")
        presenter.extend()
        presenter.extend(dwells: false)
        try? await Task.sleep(for: .milliseconds(250))
        assert(presenter.isShowing, "A new repeat must cancel a previous dismissal timer")
        presenter.extend()
        for _ in 0..<100 where presenter.isShowing { try? await Task.sleep(for: .milliseconds(20)) }
        assert(!presenter.isShowing, "Final readback must restore automatic dismissal")
        presenter.show(Text("60%"), size: CGSize(width: 100, height: 100), dwells: false)
        presenter.dismiss()
        assert(!presenter.isShowing, "Disable or shutdown must dismiss pending feedback")
        print("HUD pending, repeat, settlement and cancellation timing passed")
    }
}
