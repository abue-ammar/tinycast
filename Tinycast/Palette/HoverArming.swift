import CoreGraphics

/// When pointer movement is choosing a row rather than drift; arming lives on `PaletteState`.
enum HoverArming {
    /// A wheel click nudges the mouse a point or two, and a gesture ends with no displacement.
    private static let slop: CGFloat = 3

    static func isDeliberate(_ pointer: CGPoint, from anchor: CGPoint) -> Bool {
        hypot(pointer.x - anchor.x, pointer.y - anchor.y) > slop
    }
}
