import CoreGraphics
import Foundation

@main
struct PaletteDisplayTest {
    static func main() {
        var failures = 0
        var checks = 0
        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            checks += 1
            if !condition() {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        let primary = screen(1, CGRect(x: 0, y: 0, width: 1440, height: 900))
        let right = screen(2, CGRect(x: 1440, y: -180, width: 2560, height: 1440))
        let above = screen(3, CGRect(x: 0, y: -1200, width: 1920, height: 1200))
        let left = screen(4, CGRect(x: -1920, y: 0, width: 1920, height: 1080))
        let screens = [right, above, primary, left]
        let focused = CGRect(x: 1700, y: 100, width: 900, height: 700)

        func selected(
            _ display: PaletteDisplay, frame: CGRect? = focused, mouse: Int? = 4,
            on candidates: [WindowPlacementEngine.Screen] = screens
        ) -> Int? {
            PaletteDisplaySelection.screen(
                for: display, screens: candidates, mouseScreenID: mouse,
                focusedWindowFrame: frame)?.id
        }

        check("focused display wins over mouse and primary", selected(.focusedWindow) == 2)
        check("mouse mode ignores the focused window", selected(.mouse) == 4)
        check("primary mode finds the origin rather than the first display", selected(.primary) == 1)
        check("window above the primary uses negative AX coordinates",
              selected(.focusedWindow, frame: CGRect(x: 100, y: -1000, width: 800, height: 600)) == 3)
        check("window left of the primary uses negative AX coordinates",
              selected(.focusedWindow, frame: CGRect(x: -1700, y: 100, width: 800, height: 600)) == 4)
        check("spanning window uses its largest overlap",
              selected(.focusedWindow, frame: CGRect(x: 1200, y: 100, width: 1000, height: 600)) == 2)
        check("equal overlap has a stable screen-order tie break",
              selected(.focusedWindow, frame: CGRect(x: 1240, y: 100, width: 400, height: 600)) == 2)
        check("fullscreen window uses the full display frame", selected(.focusedWindow, frame: right.frame) == 2)
        check("unavailable focus or permission falls back to mouse", selected(.focusedWindow, frame: nil) == 4)
        check("missing mouse and focus fall back to primary",
              selected(.focusedWindow, frame: nil, mouse: nil) == 1)
        check("missing mouse does not discard valid focus", selected(.focusedWindow, mouse: nil) == 2)
        check("disconnected mouse screen falls back to primary", selected(.mouse, mouse: 999) == 1)
        check("offscreen window falls back to mouse",
              selected(.focusedWindow, frame: CGRect(x: 9000, y: 0, width: 800, height: 600)) == 4)
        check("touching a display edge is not visible overlap",
              selected(.focusedWindow, frame: CGRect(x: 4000, y: 0, width: 800, height: 600)) == 4)
        for frame in [
            CGRect.zero, CGRect.null, CGRect.infinite,
            CGRect(x: 1700, y: 0, width: 0, height: 100),
            CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100)
        ] {
            check("unusable focused geometry falls back to mouse", selected(.focusedWindow, frame: frame) == 4)
        }
        for display in PaletteDisplay.allCases {
            check("no screens returns nil for \(display)", selected(display, on: []) == nil)
            check("single screen works for \(display)", selected(display, on: [primary]) == 1)
            check("stored selection survives stale cursor preference for \(display)",
                  PaletteDisplay.stored(rawValue: display.rawValue, openOnCursorScreen: true) == display)
            check("stored selection survives stale primary preference for \(display)",
                  PaletteDisplay.stored(rawValue: display.rawValue, openOnCursorScreen: false) == display)
        }
        check("legacy cursor preference is preserved",
              PaletteDisplay.stored(rawValue: nil, openOnCursorScreen: true) == .mouse)
        check("legacy primary preference is preserved",
              PaletteDisplay.stored(rawValue: nil, openOnCursorScreen: false) == .primary)
        check("unknown stored selection keeps the legacy preference",
              PaletteDisplay.stored(rawValue: "unknown", openOnCursorScreen: false) == .primary)
        check("unknown backup selection without a legacy value is ignored",
              PaletteDisplay.stored(rawValue: "unknown", openOnCursorScreen: nil) == nil)
        check("fresh installs preserve the mouse-display default",
              (PaletteDisplay.stored(rawValue: nil, openOnCursorScreen: nil) ?? .mouse) == .mouse)

        print("\(checks) checks, \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }

    private static func screen(_ id: Int, _ frame: CGRect) -> WindowPlacementEngine.Screen {
        .init(id: id, frame: frame, visibleFrame: frame.insetBy(dx: 0, dy: 30))
    }
}
