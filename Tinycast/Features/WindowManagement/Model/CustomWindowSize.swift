import CoreGraphics
import Foundation

/// A user-defined window command: one size at one position, applied to the focused window.
/// See docs/features/window-management.md#custom-sizes.
struct CustomWindowSize: Codable, Hashable, Identifiable, Sendable {
    static let entryIDPrefix = "window-size:"
    static let sfSymbol = "macwindow.and.cursorarrow"

    /// One axis's length, in the unit the user typed it in.
    struct Dimension: Codable, Hashable, Sendable {
        enum Unit: String, Codable, CaseIterable, Sendable {
            case points
            case percent

            /// Wider than any display for points, so a real size is never clipped at authoring.
            var range: ClosedRange<Int> {
                switch self {
                case .points: return 1...16_000
                case .percent: return 1...100
                }
            }

            var suffix: String {
                switch self {
                case .points: return "pt"
                case .percent: return "%"
                }
            }
        }

        var value: Int
        var unit: Unit

        init(_ value: Int, _ unit: Unit) {
            self.value = value.clamped(to: unit.range)
            self.unit = unit
        }

        var label: String {
            unit == .points ? "\(value) pt" : "\(value)%"
        }

        /// The length this asks for inside `available`, never zero and never past it.
        func length(in available: CGFloat) -> CGFloat {
            let requested =
                unit == .points ? CGFloat(value) : available * CGFloat(value) / 100
            return min(available, max(WindowLayoutGeometry.minimumLength, requested))
        }

        /// The same length restated in `unit`, measured against `available`.
        func converted(to unit: Unit, in available: CGFloat) -> Dimension {
            guard unit != self.unit, available > 0 else { return Dimension(value, unit) }
            let points = unit == .percent ? CGFloat(value) : CGFloat(value) * available / 100
            let converted = unit == .percent ? points / available * 100 : points
            return Dimension(Int(converted.rounded()), unit)
        }
    }

    let id: UUID
    var name: String
    var width: Dimension
    var height: Dimension
    var anchor: WindowLayoutAnchor

    init(
        id: UUID = UUID(), name: String, width: Dimension = Dimension(60, .percent),
        height: Dimension = Dimension(60, .percent), anchor: WindowLayoutAnchor = .center
    ) {
        self.id = id
        self.name = name
        self.width = width
        self.height = height
        self.anchor = anchor
    }

    var entryID: String { Self.entryIDPrefix + id.uuidString.lowercased() }

    /// The settings row's subtitle: what this size does, in one line.
    var summary: String { "\(width.label) × \(height.label) · \(anchor.title)" }

    static func id(fromEntryID entryID: String) -> UUID? {
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        return UUID(uuidString: String(entryID.dropFirst(entryIDPrefix.count)))
    }

    static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
        let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        guard order == .orderedSame else { return order == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// Trimmed and clamped rather than rejected, so a bad import keeps the record.
    var sanitized: CustomWindowSize {
        var cleaned = self
        cleaned.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.width = Dimension(width.value, width.unit)
        cleaned.height = Dimension(height.value, height.unit)
        return cleaned
    }

    // MARK: - Geometry

    /// The frame this size asks for on a display, in AX space; nil when the display has no room.
    func frame(in visibleFrame: CGRect, gap: CGFloat) -> CGRect? {
        let canvas = WindowPlacementEngine.canvas(
            visibleFrame, gap: WindowPlacementEngine.sanitizedGap(gap, in: visibleFrame))
        guard canvas.width > 0, canvas.height > 0 else { return nil }
        let size = CGSize(
            width: width.length(in: canvas.width), height: height.length(in: canvas.height))
        return WindowPlacementEngine.rounded(anchor.placement.place(size, in: canvas))
    }

    /// Where this size puts a window, on the display the window is already on.
    func placement(
        for windowFrame: CGRect, screens: [WindowPlacementEngine.Screen], gap: CGFloat
    ) -> WindowPlacementEngine.Placement? {
        guard let host = WindowPlacementEngine.screen(containing: windowFrame, in: screens),
            let frame = frame(in: host.visibleFrame, gap: gap)
        else { return nil }
        return WindowPlacementEngine.Placement(
            frame: frame, screenID: host.id, anchor: anchor.placement, resizes: true)
    }
}

enum CustomWindowSizeValidationError: LocalizedError, Equatable {
    case emptyName
    case duplicateName
    case invalidCharacter

    var errorDescription: String? {
        switch self {
        case .emptyName: return "Enter a name for the size."
        case .duplicateName: return "A custom size with this name already exists."
        case .invalidCharacter: return "Names cannot contain null characters."
        }
    }
}

extension Int {
    /// Saturating, so a typed or imported number is corrected rather than rejected.
    fileprivate func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
