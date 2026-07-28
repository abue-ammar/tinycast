import Carbon.HIToolbox
import CoreGraphics

/// The physical key remapped to the Hyper chord (⌃⌥⇧⌘). String raw values are the `AppSettings` persistence format (renaming a case is a migration; a removed case decodes to `.none`); `allCases` is the picker order. F-keys were dropped — top-row media functions fire below the tap, so F1-as-Hyper still dimmed the display.
enum HyperKeyPhysicalKey: String, CaseIterable, Identifiable, Sendable {
    case none
    case capsLock
    case rightControl, rightShift, rightOption, rightCommand

    var id: String { rawValue }

    /// The single glyph Hyper shortcuts collapse to, Raycast-style.
    static let hyperGlyph = "✦"

    var title: String {
        switch self {
        case .none: return "None"
        case .capsLock: return "Caps Lock (⇪)"
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
        case .rightControl: return kVK_RightControl
        case .rightShift: return kVK_RightShift
        case .rightOption: return kVK_RightOption
        case .rightCommand: return kVK_RightCommand
        }
    }

    /// The keycode the tap watches: Caps Lock is HID-remapped to F18 while it serves as Hyper (see `CapsLockRemap`), so the tap intercepts F18 in its place.
    var tapKeyCode: Int? {
        self == .capsLock ? kVK_F18 : keyCode
    }

    /// Whether the tap sees presses as keyDown/keyUp (Caps Lock via F18) or as `flagsChanged` transitions (the real modifier keys).
    var tapUsesKeyEvents: Bool { self == .capsLock }

    /// Keys that do something on their own when not remapped — these get the Quick Press row.
    var hasOriginalFunction: Bool { self == .capsLock }

    /// The generic `CGEventFlags` bit this key contributes, so the tap can strip it when the key sits outside the synthetic Hyper set.
    var ownFlag: CGEventFlags? {
        switch self {
        case .none: return nil
        case .capsLock: return .maskAlphaShift
        case .rightControl: return .maskControl
        case .rightShift: return .maskShift
        case .rightOption: return .maskAlternate
        case .rightCommand: return .maskCommand
        }
    }

    /// Quick Press label for triggering the key's original function.
    var quickPressOriginalTitle: String? {
        self == .capsLock ? "Trigger Caps Lock (⇪)" : nil
    }
}

/// What a quick lone press of the Hyper key does (only offered for keys with an original function).
enum HyperKeyQuickPress: String, CaseIterable, Sendable {
    case none
    case originalKey
    case escape
}
