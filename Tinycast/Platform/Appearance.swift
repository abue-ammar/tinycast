import AppKit

extension NSAppearance {
    /// `bestMatch`, not a name comparison, so vibrant and accessibility variants resolve.
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

extension NSColor {
    /// Built in sRGB, where `Color.white` resolves, so a dark branch is the same pixel.
    static func srgbInk(_ white: CGFloat, alpha: Double) -> NSColor {
        NSColor(srgbRed: white, green: white, blue: white, alpha: alpha)
    }
}
