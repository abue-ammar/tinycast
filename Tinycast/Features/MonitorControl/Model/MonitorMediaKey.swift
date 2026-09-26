// Event decoding follows MediaKeyTap, © Nicholas Hurden and contributors; MIT in NOTICE.md.
import Foundation

struct MonitorMediaKey: Sendable {
    enum Action: Int, Sendable {
        case volumeUp = 0, volumeDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7

        var control: MonitorControlKind {
            switch self {
            case .brightnessUp, .brightnessDown: .brightness
            case .volumeUp, .volumeDown: .volume
            case .mute: .mute
            }
        }

        var up: Bool { self == .brightnessUp || self == .volumeUp }
    }

    let action: Action
    let pressed: Bool
    let repeated: Bool
    let flags: UInt64
    let token: Int

    var fine: Bool { flags & (1 << 17 | 1 << 19) == (1 << 17 | 1 << 19) }
    var supportedModifiers: Bool {
        let modifiers = flags & (1 << 17 | 1 << 18 | 1 << 19 | 1 << 20)
        return modifiers == 0 || modifiers == (1 << 17) || modifiers == (1 << 17 | 1 << 19)
    }

    static func decode(
        type: UInt32, subtype: Int, data: Int, keyCode: Int, repeated: Bool, flags: UInt64
    ) -> Self? {
        if type == 14, subtype == 8 {
            guard let action = Action(rawValue: (data >> 16) & 0xFFFF) else { return nil }
            let state = (data >> 8) & 0xFF
            guard state == 0xA || state == 0xB else { return nil }
            return Self(action: action, pressed: state == 0xA, repeated: data & 1 != 0,
                        flags: flags, token: action.rawValue)
        }
        guard type == 10 || type == 11, keyCode == 144 || keyCode == 145 else { return nil }
        return Self(action: keyCode == 144 ? .brightnessUp : .brightnessDown,
                    pressed: type == 10, repeated: repeated, flags: flags, token: keyCode)
    }
}
