import Foundation

enum ModifierKey: String, CaseIterable, Codable, Sendable {
    case leftControl, rightControl
    case leftOption, rightOption
    case leftShift, rightShift
    case leftCommand, rightCommand
    case globe

    static let globeGlyph = "🌐︎"

    var modifier: DoubleTapModifier? {
        switch self {
        case .leftControl, .rightControl: .control
        case .leftOption, .rightOption: .option
        case .leftShift, .rightShift: .shift
        case .leftCommand, .rightCommand: .command
        case .globe: nil
        }
    }

    var side: String? {
        switch self {
        case .leftControl, .leftOption, .leftShift, .leftCommand: String(localized: "Left")
        case .rightControl, .rightOption, .rightShift, .rightCommand: String(localized: "Right")
        case .globe: nil
        }
    }

    var keycaps: [String] { (side.map { [$0] } ?? []) + [modifier?.glyph ?? Self.globeGlyph] }

    var singleBinding: HotKeyBinding { self == .globe ? .globe : .modifier(self) }
    var doubleBinding: HotKeyBinding { self == .globe ? .doubleGlobe : .doubleModifier(self) }

    // Device masks identify both keys even when their shared, generic modifier bit stays set.
    var deviceMask: UInt64 {
        switch self {
        case .leftControl: 0x0001
        case .rightControl: 0x2000
        case .leftOption: 0x0020
        case .rightOption: 0x0040
        case .leftShift: 0x0002
        case .rightShift: 0x0004
        case .leftCommand: 0x0008
        case .rightCommand: 0x0010
        case .globe: 0
        }
    }

    static func held(in flags: UInt64, globeDown: Bool) -> Set<Self> {
        var held = Set(allCases.filter { $0.deviceMask & flags != 0 })
        if globeDown { held.insert(.globe) }
        return held
    }

    func isHeld(in flags: UInt64) -> Bool { deviceMask & flags != 0 }

    func otherSideIsHeld(in flags: UInt64) -> Bool {
        Self.allCases.contains { $0 != self && $0.modifier == modifier && $0.isHeld(in: flags) }
    }
}
