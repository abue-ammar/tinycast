import AppKit
import SwiftUI

enum MonitorHUDController {
    struct State {
        let symbol = "sun.max.fill"
        let level = 0.5
        let label = "50%"
        let name = "Monitor"
    }
}

@main
@MainActor
struct MonitorHUDLayoutTests {
    static func main() {
        _ = NSApplication.shared
        for size in InterfaceSize.allCases {
            let metrics = size.metrics
            let content = MonitorHUDView(state: .init()).environment(\.metrics, metrics)
            let host = NSHostingView(rootView: content)
            let expected = CGSize(width: metrics.size.hudWidth, height: metrics.size.hudHeight)
            assert(host.fittingSize == expected, "HUD content must fit the panel at \(size)")
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: expected),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            host.frame.size = expected
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                fatalError("Could not render HUD at \(size)")
            }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            assert(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
        }
        print("Monitor HUD layout fits every interface size")
    }
}
