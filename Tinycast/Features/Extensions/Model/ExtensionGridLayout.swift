import Foundation

/// A `Grid`'s layout props: the tile shape and how an item's content sits inside it.
struct ExtensionGridLayout: Equatable, Sendable {
    /// Space between a tile's border and its content. Raycast scales it with the tile, so this does.
    enum Inset: String, Sendable {
        case zero
        case small = "sm"
        case medium = "md"
        case large = "lg"

        var fraction: Double {
            switch self {
            case .zero: return 0
            case .small: return 0.08
            case .medium: return 0.16
            case .large: return 0.24
            }
        }
    }

    /// The tile's own corner, owned here rather than in `Theme`: no launcher surface is this size.
    static let tileRadius: Double = 12

    /// Raycast clamps to 1…8.
    var columns: Int
    /// Tile width ÷ height.
    var aspectRatio: Double
    /// `Grid.Fit.Fill` crops content to the tile; `.Contain` fits it inside.
    var fills: Bool
    var inset: Inset

    init(columns: Int = 5, aspectRatio: Double = 1, fills: Bool = false, inset: Inset = .zero) {
        self.columns = min(max(columns, 1), 8)
        self.aspectRatio = aspectRatio > 0 ? aspectRatio : 1
        self.fills = fills
        self.inset = inset
    }

    init(_ root: RenderNode) {
        self.init(
            columns: ExtensionGridLayout.columns(root),
            aspectRatio: ExtensionGridLayout.ratio(root.string("aspectRatio")) ?? 1,
            fills: root.string("fit") == "fill",
            inset: root.string("inset").flatMap(Inset.init(rawValue:)) ?? .zero)
    }

    /// Tile width for the space the grid is given, so one measure feeds every cell.
    func tileWidth(inWidth width: Double, spacing: Double) -> Double {
        max(1, (width - spacing * Double(columns - 1)) / Double(columns))
    }

    private static func columns(_ root: RenderNode) -> Int {
        if let columns = root.double("columns").map({ Int($0) }), columns > 0 { return columns }
        // Raycast's default is 5; `itemSize` is the legacy way of saying the same thing.
        switch root.string("itemSize") {
        case "small": return 8
        case "large": return 3
        default: return 5
        }
    }

    /// `aspectRatio` arrives as `"1"` or `"16/9"`.
    private static func ratio(_ text: String?) -> Double? {
        guard let text else { return nil }
        let parts = text.split(separator: "/").compactMap { Double($0) }
        switch parts.count {
        case 1: return parts[0] > 0 ? parts[0] : nil
        case 2: return parts[0] > 0 && parts[1] > 0 ? parts[0] / parts[1] : nil
        default: return nil
        }
    }
}
