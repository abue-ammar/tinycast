import Foundation

enum MonitorControlAdjustment: Sendable {
    case level(offset: Int, minimum: Int, maximum: Int)
    case mute(toggle: Bool)

    static func step(from current: MonitorControlValue, to next: MonitorControlValue, up: Bool, fine: Bool) -> Self {
        var delta = Int(next.current) - Int(current.current)
        if delta == 0 {
            delta = max(1, Int((Double(current.maximum) / (fine ? 64 : 16)).rounded())) * (up ? 1 : -1)
        }
        let maximum = Int(current.maximum)
        return .level(offset: delta, minimum: max(0, min(maximum, delta)),
                      maximum: max(0, min(maximum, maximum + delta)))
    }

    func apply(to value: MonitorControlValue) -> MonitorControlValue {
        switch self {
        case .mute(let toggle):
            return toggle ? value.toggledMute : value
        case .level(let offset, let minimum, let maximum):
            let raw = min(maximum, max(minimum, Int(value.current) + offset))
            return .init(current: UInt16(min(Int(value.maximum), max(0, raw))), maximum: value.maximum)
        }
    }

    func followed(by next: Self) -> Self {
        switch (self, next) {
        case (.mute(let first), .mute(let second)):
            return .mute(toggle: first != second)
        case (.level(let offset, let minimum, let maximum), .level(let shift, let lower, let upper)):
            let newLower = min(upper, max(lower, minimum + shift))
            let newUpper = min(upper, max(lower, maximum + shift))
            return .level(offset: newLower == newUpper ? 0 : offset + shift, minimum: newLower, maximum: newUpper)
        default:
            return next
        }
    }
}
