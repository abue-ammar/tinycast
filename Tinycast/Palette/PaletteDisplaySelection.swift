import CoreGraphics

enum PaletteDisplaySelection {
    static func screen(
        for display: PaletteDisplay, screens: [WindowPlacementEngine.Screen],
        mouseScreenID: Int?, focusedWindowFrame: CGRect?
    ) -> WindowPlacementEngine.Screen? {
        let primary = screens.first { $0.frame.origin == .zero } ?? screens.first
        let mouse = screens.first { $0.id == mouseScreenID } ?? primary
        switch display {
        case .primary: return primary
        case .mouse: return mouse
        case .focusedWindow:
            guard let frame = focusedWindowFrame,
                !frame.isNull, !frame.isInfinite,
                frame.origin.x.isFinite, frame.origin.y.isFinite,
                frame.width.isFinite, frame.height.isFinite,
                frame.width > 0, frame.height > 0,
                screens.contains(where: {
                    let overlap = $0.frame.intersection(frame)
                    return overlap.width > 0 && overlap.height > 0
                })
            else { return mouse }
            return WindowPlacementEngine.screen(containing: frame, in: screens) ?? mouse
        }
    }
}
