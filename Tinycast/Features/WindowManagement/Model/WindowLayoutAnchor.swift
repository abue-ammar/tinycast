import CoreGraphics

/// The 3×3 position grid. Raw values are spelled out so renaming a case can't rename a stored one.
enum WindowLayoutAnchor: String, Codable, CaseIterable, Sendable {
    case topLeft = "top-left"
    case top
    case topRight = "top-right"
    case left
    case center
    case right
    case bottomLeft = "bottom-left"
    case bottom
    case bottomRight = "bottom-right"

    /// `place(_:in:)` stays the only anchor arithmetic in the codebase; this is just the spelling.
    var placement: WindowPlacementEngine.Anchor {
        WindowPlacementEngine.Anchor(horizontal: horizontal, vertical: vertical)
    }

    /// The accessibility label for the grid button, and the name a settings row shows.
    var title: String {
        switch self {
        case .topLeft: return "Top Left"
        case .top: return "Top"
        case .topRight: return "Top Right"
        case .left: return "Left"
        case .center: return "Center"
        case .right: return "Right"
        case .bottomLeft: return "Bottom Left"
        case .bottom: return "Bottom"
        case .bottomRight: return "Bottom Right"
        }
    }

    private var horizontal: WindowPlacementEngine.Anchor.Axis {
        switch self {
        case .topLeft, .left, .bottomLeft: return .min
        case .top, .center, .bottom: return .center
        case .topRight, .right, .bottomRight: return .max
        }
    }

    /// `.min` is the top, since +Y points down in the AX space every frame here lives in.
    private var vertical: WindowPlacementEngine.Anchor.Axis {
        switch self {
        case .topLeft, .top, .topRight: return .min
        case .left, .center, .right: return .center
        case .bottomLeft, .bottom, .bottomRight: return .max
        }
    }

    /// The one place an axis pair maps back to a case, so the grid and `describe` agree.
    static func named(
        horizontal: WindowPlacementEngine.Anchor.Axis, vertical: WindowPlacementEngine.Anchor.Axis
    ) -> WindowLayoutAnchor {
        switch (horizontal, vertical) {
        case (.min, .min): return .topLeft
        case (.center, .min): return .top
        case (.max, .min): return .topRight
        case (.min, .center): return .left
        case (.center, .center): return .center
        case (.max, .center): return .right
        case (.min, .max): return .bottomLeft
        case (.center, .max): return .bottom
        case (.max, .max): return .bottomRight
        }
    }
}
