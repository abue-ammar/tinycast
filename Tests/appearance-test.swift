import AppKit
import SwiftUI

/// Pins `AGENTS.md`: a token's dark branch is the literal the forced-dark build shipped.
@main
@MainActor
struct AppearanceTests {
    static var failures = 0
    static var passes = 0

    static func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        if ok {
            passes += 1
        } else {
            failures += 1
            print("FAIL  \(label)\(detail.isEmpty ? "" : ": \(detail)")")
        }
    }

    /// Quantized to the 8 bits that reach the framebuffer: `CGFloat`s carry Float error.
    static func components(_ color: Color, _ name: NSAppearance.Name) -> [Int] {
        var out: [Int] = []
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            let ns = NSColor(color).usingColorSpace(.sRGB)!
            out = [ns.redComponent, ns.greenComponent, ns.blueComponent, ns.alphaComponent]
                .map { Int(($0 * 255).rounded()) }
        }
        return out
    }

    static func dark(_ label: String, _ token: Color, is expected: Color) {
        let actual = components(token, .darkAqua)
        let wanted = components(expected, .darkAqua)
        check("dark \(label)", actual == wanted, "\(actual) != \(wanted)")
    }

    /// A token that resolves identically in both never adapted at all.
    static func adapts(_ label: String, _ token: Color) {
        check(
            "\(label) adapts", components(token, .darkAqua) != components(token, .aqua),
            "light resolves identically to dark")
    }

    static func main() {
        let c = Theme.Colors.self

        print("# dark branches are the shipped literals")
        dark("panelScrim", c.panelScrim, is: Color.black.opacity(0.4))
        dark("selection", c.selection, is: Color.white.opacity(0.10))
        dark("rowHover", c.rowHover, is: Color.white.opacity(0.05))
        dark("menuHover", c.menuHover, is: Color.white.opacity(0.10))
        dark("separator", c.separator, is: Color.white.opacity(0.10))
        dark("controlSurface", c.controlSurface, is: Color.white.opacity(0.10))
        dark("border", c.border, is: Color.white.opacity(0.20))
        dark("textSecondary", c.textSecondary, is: Color.white.opacity(0.60))
        dark("textTertiary", c.textTertiary, is: Color.white.opacity(0.40))
        dark("noteText", c.noteText, is: Color.white.opacity(0.90))
        dark("cardFill", c.cardFill, is: Color.white.opacity(0.05))
        dark("cardStroke", c.cardStroke, is: Color.white.opacity(0.10))
        dark("glassFrost", c.glassFrost, is: Color.white.opacity(0.05))
        dark("dropGuide", c.dropGuide, is: Color.white.opacity(0.35))
        dark("brand", c.brand, is: Color(red: 0.525, green: 0.231, blue: 1.0))

        print("# tokens that absorbed a literal duplicated across views")
        dark("iconPlaceholder", c.iconPlaceholder, is: Color.white.opacity(0.06))
        dark("sheen", c.sheen, is: Color.white.opacity(0.04))
        dark("textPrimary", c.textPrimary, is: Color.white)
        // VolumeSlider drew white 0.85; textPrimary is alpha 1, so `.opacity` has to reproduce it.
        dark("textPrimary at 0.85", c.textPrimary.opacity(0.85), is: Color.white.opacity(0.85))

        print("# every surface token resolves per appearance")
        for (label, token) in [
            ("panelScrim", c.panelScrim), ("selection", c.selection), ("rowHover", c.rowHover),
            ("menuHover", c.menuHover), ("separator", c.separator),
            ("controlSurface", c.controlSurface), ("border", c.border),
            ("textPrimary", c.textPrimary), ("textSecondary", c.textSecondary),
            ("textTertiary", c.textTertiary), ("noteText", c.noteText), ("cardFill", c.cardFill),
            ("cardStroke", c.cardStroke), ("glassFrost", c.glassFrost), ("dropGuide", c.dropGuide),
            ("iconPlaceholder", c.iconPlaceholder), ("sheen", c.sheen)
        ] {
            adapts(label, token)
        }

        print("# the scrim inverts rather than ramping: it lightens the light surface")
        check("light scrim is white", components(c.panelScrim, .aqua)[0] == 255)
        check("dark scrim is black", components(c.panelScrim, .darkAqua)[0] == 0)
        // Frost brightens glass in both, so it is the one token that stays white either side.
        check("frost stays white", components(c.glassFrost, .aqua)[0] == 255)

        print("# .system hands the choice back to AppKit")
        check("system is nil", AppAppearance.system.nsAppearance == nil)
        check("light is aqua", AppAppearance.light.nsAppearance?.isDark == false)
        check("dark is darkAqua", AppAppearance.dark.nsAppearance?.isDark == true)
        check("an unknown stored value is rejected", AppAppearance(rawValue: "sepia") == nil)

        print("\n\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
