import Foundation

/// A native-looking stand-in for an extension's icon: a curated symbol on a tinted tile.
struct ExtensionAppearance: Codable, Equatable, Hashable, Sendable {
    var symbol: String
    var tint: ExtensionTint

    static let fallback = ExtensionAppearance(symbol: "puzzlepiece.extension", tint: .purple)
}

/// The Settings sidebar's own family, so an override belongs rather than sticks out.
enum ExtensionTint: String, CaseIterable, Identifiable, Codable, Sendable {
    // Declaration order is swatch order: around the wheel, then the earths and neutrals.
    case red, maroon, rose, pink, purple, indigo, blue, cyan, teal, mint
    case green, lime, yellow, orange, tan, brown, gray, slate

    var id: String { rawValue }

    /// Shown as the swatch tooltip — "tan" alone doesn't say much.
    var title: String {
        switch self {
        case .tan: return "Light Brown"
        case .maroon: return "Maroon"
        case .slate: return "Slate"
        default: return rawValue.capitalized
        }
    }
}
