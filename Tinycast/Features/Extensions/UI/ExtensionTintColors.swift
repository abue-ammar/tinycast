import AppKit
import SwiftUI

/// What a tint actually paints with. Split from the `Model/` type so that stays Foundation-only.
extension ExtensionTint {
    /// Fixed sRGB, not the system colours: the tile is rasterized off the main thread, where a dynamic
    /// colour would resolve against whatever appearance that thread happens to see. Pinning the values
    /// also guarantees the picker's SwiftUI preview and the drawn bitmap are the same colour. These are
    /// Apple's dark-mode system values, which is the only appearance the app runs in.
    private var components: (red: Double, green: Double, blue: Double) {
        switch self {
        case .red: return (1.00, 0.27, 0.23)
        case .maroon: return (0.62, 0.24, 0.24)
        case .rose: return (1.00, 0.45, 0.53)
        case .pink: return (1.00, 0.22, 0.37)
        case .purple: return (0.75, 0.35, 0.95)
        case .indigo: return (0.37, 0.36, 0.90)
        case .blue: return (0.04, 0.52, 1.00)
        case .cyan: return (0.39, 0.82, 1.00)
        case .teal: return (0.25, 0.78, 0.88)
        case .mint: return (0.40, 0.83, 0.81)
        case .green: return (0.20, 0.84, 0.29)
        case .lime: return (0.64, 0.86, 0.24)
        case .yellow: return (1.00, 0.84, 0.04)
        case .orange: return (1.00, 0.62, 0.04)
        case .tan: return (0.84, 0.70, 0.52)
        case .brown: return (0.67, 0.53, 0.38)
        case .gray: return (0.60, 0.60, 0.62)
        case .slate: return (0.44, 0.50, 0.58)
        }
    }

    var color: Color {
        let rgb = components
        return Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    /// What `IconCache` actually draws with — the same values, as AppKit sees them.
    var nsColor: NSColor {
        let rgb = components
        return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }

    var symbolTint: SymbolTint { SymbolTint(key: rawValue, color: nsColor) }
}
