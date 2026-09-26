import Foundation

enum MonitorControlKind: UInt8, CaseIterable, Sendable {
    case brightness = 0x10
    case volume = 0x62
    case mute = 0x8D
}

struct MonitorControlValue: Equatable, Sendable {
    var current: UInt16
    var maximum: UInt16

    var fraction: Double { maximum > 0 ? Double(current) / Double(maximum) : 0 }

    func stepped(up: Bool, fine: Bool) -> Self {
        guard maximum > 0 else { return self }
        let steps = fine ? 64.0 : 16.0
        let position = fraction * steps
        let nearest = position.rounded()
        let onGrid = (nearest * Double(maximum) / steps).rounded() == Double(current)
        let line = onGrid ? nearest : (up ? floor(position) : ceil(position))
        let target = ((line + (up ? 1 : -1)) * Double(maximum) / steps).rounded()
        let next = min(Double(maximum), max(0, up ? max(Double(current) + 1, target) : min(Double(current) - 1, target)))
        return Self(current: UInt16(next), maximum: maximum)
    }

    var toggledMute: Self { Self(current: current == 1 ? 2 : 1, maximum: maximum) }
}
