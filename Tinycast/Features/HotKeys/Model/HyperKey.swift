import Carbon.HIToolbox
import CoreGraphics

enum HyperKeyPhysicalKey: String, CaseIterable, Identifiable, Sendable {
    case none
    case capsLock
    case leftControl, leftShift, leftOption, leftCommand
    case rightControl, rightShift, rightOption, rightCommand

    var id: String { rawValue }

    static let hyperGlyph = "✦"

    var title: String {
        switch self {
        case .none: return "None"
        case .capsLock: return "Caps Lock (⇪)"
        case .leftControl: return "Left Control (⌃)"
        case .leftShift: return "Left Shift (⇧)"
        case .leftOption: return "Left Option (⌥)"
        case .leftCommand: return "Left Command (⌘)"
        case .rightControl: return "Right Control (⌃)"
        case .rightShift: return "Right Shift (⇧)"
        case .rightOption: return "Right Option (⌥)"
        case .rightCommand: return "Right Command (⌘)"
        }
    }

    /// Virtual key code of the physical key, `nil` only for `.none`.
    var keyCode: Int? {
        switch self {
        case .none: return nil
        case .capsLock: return kVK_CapsLock
        case .leftControl: return kVK_Control
        case .leftShift: return kVK_Shift
        case .leftOption: return kVK_Option
        case .leftCommand: return kVK_Command
        case .rightControl: return kVK_RightControl
        case .rightShift: return kVK_RightShift
        case .rightOption: return kVK_RightOption
        case .rightCommand: return kVK_RightCommand
        }
    }

    /// Keys that do something on their own when not remapped — these get the Quick Press row.
    var hasOriginalFunction: Bool { self == .capsLock }

    var supportsSecureInputCompatibility: Bool { self == .capsLock }

    /// The generic flag this key contributes, so the tap can strip it when outside the set.
    var ownFlag: CGEventFlags? {
        switch self {
        case .none: return nil
        case .capsLock: return .maskAlphaShift
        case .leftControl, .rightControl: return .maskControl
        case .leftShift, .rightShift: return .maskShift
        case .leftOption, .rightOption: return .maskAlternate
        case .leftCommand, .rightCommand: return .maskCommand
        }
    }

    var quickPressOriginalTitle: String? {
        self == .capsLock ? "Trigger Caps Lock (⇪)" : nil
    }

    func route(secureInputCompatible: Bool) -> HyperKeyRoute? {
        guard let keyCode else { return nil }
        guard self == .capsLock else {
            return HyperKeyRoute(key: self, tapKeyCode: keyCode, modifier: modifierKey, remap: nil)
        }
        // Secure Input still delivers modifiers, so this variant sends Right Control, not F18.
        if secureInputCompatible {
            return HyperKeyRoute(
                key: self, tapKeyCode: kVK_RightControl, modifier: .rightControl,
                remap: .capsLockToRightControl)
        }
        return HyperKeyRoute(key: self, tapKeyCode: kVK_F18, modifier: nil, remap: .capsLockToF18)
    }

    private var modifierKey: ModifierKey? {
        switch self {
        case .none, .capsLock: return nil
        case .leftControl: return .leftControl
        case .leftShift: return .leftShift
        case .leftOption: return .leftOption
        case .leftCommand: return .leftCommand
        case .rightControl: return .rightControl
        case .rightShift: return .rightShift
        case .rightOption: return .rightOption
        case .rightCommand: return .rightCommand
        }
    }
}

struct HyperKeyRoute: Equatable, Sendable {
    let key: HyperKeyPhysicalKey
    let tapKeyCode: Int
    /// Whose device bit tells press from release; nil for F18, which arrives as keyDown/keyUp.
    let modifier: ModifierKey?
    let remap: HIDKeyMapping?
}

/// What a quick lone press of the Hyper key does (only offered for keys with an original function).
enum HyperKeyQuickPress: String, CaseIterable, Sendable {
    case none
    case originalKey
    case escape
}
