import AppKit
import SwiftUI

@main
@MainActor
struct MonitorSettingsTests {
    static func main() {
        _ = NSApplication.shared
        for scheme in [ColorScheme.light, .dark] {
            for active in [true, false] {
                for enabled in [true, false] {
                    let content = Form {
                        Toggle("Enable external monitor control", isOn: .constant(enabled))
                            .toggleStyle(MonitorControlToggleStyle())
                    }
                    .formStyle(.grouped)
                    .environment(\.appearsActive, active)
                    .environment(\.colorScheme, scheme)
                    let host = NSHostingView(rootView: content)
                    let bounds = NSRect(x: 0, y: 0, width: 600, height: 100)
                    let window = NSWindow(contentRect: bounds, styleMask: [.titled], backing: .buffered, defer: false)
                    window.contentView = host
                    host.frame = bounds
                    host.layoutSubtreeIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                        fatalError("Could not render monitor control switch")
                    }
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    let blue = bluePixelCount(bitmap)
                    assert(enabled ? blue > 100 : blue < 100,
                           "On must remain blue and off neutral in \(scheme), active=\(active)")
                }
            }
        }
        print("Monitor switch on/off colors passed in light/dark and active/inactive appearances")
    }

    private static func bluePixelCount(_ bitmap: NSBitmapImageRep) -> Int {
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.blueComponent > 0.5, color.blueComponent > color.redComponent * 1.5,
                    color.blueComponent > color.greenComponent * 1.1 {
                    count += 1
                }
            }
        }
        return count
    }
}
