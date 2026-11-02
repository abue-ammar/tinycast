import Foundation

extension CustomWindowSize {
    init?(linkFields fields: [String: String]) {
        guard let width = fields["width"].flatMap(Dimension.init(linkValue:)),
            let height = fields["height"].flatMap(Dimension.init(linkValue:)),
            let anchor = Self.anchor(fields["anchor"]),
            let x = Self.offset(fields["x"]), let y = Self.offset(fields["y"])
        else { return nil }
        self.init(name: "", width: width, height: height, anchor: anchor, offset: Offset(x: x, y: y))
    }

    private static func anchor(_ value: String?) -> WindowLayoutAnchor? {
        guard let value else { return .center }
        return WindowLayoutAnchor(rawValue: value.lowercased())
    }

    private static func offset(_ value: String?) -> Int? {
        guard let value else { return 0 }
        return Int(value).flatMap { Offset.range.contains($0) ? $0 : nil }
    }
}

extension CustomWindowSize.Dimension {
    /// `1200` is points and `60%` a share of the screen; out of range is refused, never clamped.
    init?(linkValue: String) {
        let trimmed = linkValue.trimmingCharacters(in: .whitespaces)
        let unit: Unit = trimmed.hasSuffix("%") ? .percent : .points
        let digits = unit == .percent ? String(trimmed.dropLast()) : trimmed
        guard let value = Int(digits), unit.range.contains(value) else { return nil }
        self.init(value, unit)
    }
}
