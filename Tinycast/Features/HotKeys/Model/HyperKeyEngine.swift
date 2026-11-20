import Carbon.HIToolbox
import CoreGraphics
import Foundation

struct HyperKeyEngine: Sendable {
    enum Decision: Equatable, Sendable {
        case pass
        case suppress
        case rewrite(flags: UInt64, keyCode: Int64? = nil, asFlagsChanged: Bool = false)
    }

    enum Effect: Equatable, Sendable {
        case unusedPress(heldFor: TimeInterval)
        case unmappedCapsLock
    }

    struct Result: Equatable, Sendable {
        var decision: Decision
        var effect: Effect?
    }

    var route: HyperKeyRoute?
    var includesShift = true
    private(set) var isActive = false
    private var downAt: TimeInterval?
    private var used = false
    private var forwarded: ForwardedQuickPress?
    private(set) var quickPressGeneration: UInt64 = 0

    mutating func setForwarding(_ enabled: Bool) {
        guard enabled != (forwarded != nil) else { return }
        cancelQuickPress()
        forwarded = enabled ? ForwardedQuickPress() : nil
    }

    mutating func physicalRelease(timestamp: UInt64, heldFor duration: TimeInterval) -> TimeInterval? {
        forwarded?.confirm(.keyboard, timestamp: timestamp, duration: duration)
    }

    private mutating func cancelQuickPress() {
        downAt = nil
        if forwarded != nil { forwarded = ForwardedQuickPress() }
        quickPressGeneration &+= 1
    }

    private enum DeviceFlags {
        static let leftControlOptionCommand: UInt64 = 0x29
        static let leftShift: UInt64 = 0x2
    }

    private var hyperFlags: UInt64 {
        var flags =
            CGEventFlags([.maskControl, .maskAlternate, .maskCommand]).rawValue
            | DeviceFlags.leftControlOptionCommand
        if includesShift { flags |= CGEventFlags.maskShift.rawValue | DeviceFlags.leftShift }
        return flags
    }

    /// A modifier's device bit says whether it is down; F18 has none, so its hold is tracked.
    private func isHeld(in flags: UInt64) -> Bool {
        route?.modifier?.isHeld(in: flags) ?? isActive
    }

    private func removingSourceFlags(from flags: UInt64) -> UInt64 {
        guard let route else { return flags }
        guard route.key != .capsLock else {
            return flags & ~(CGEventFlags.maskAlphaShift.rawValue | (route.modifier?.deviceMask ?? 0))
        }
        guard let modifier = route.modifier, let own = route.key.ownFlag?.rawValue else { return flags }
        let flags = flags & ~modifier.deviceMask
        guard hyperFlags & own == 0, !modifier.otherSideIsHeld(in: flags) else { return flags }
        return flags & ~own
    }

    /// True when a release must be synthesized: a modifier's own release still reaches the tap.
    @discardableResult
    mutating func reset() -> Bool {
        cancelQuickPress()
        return endHold()
    }

    @discardableResult
    private mutating func endHold() -> Bool {
        let needsRelease = isActive && route?.modifier == nil
        isActive = false
        downAt = nil
        used = false
        return needsRelease
    }

    mutating func handle(
        type: CGEventType, keyCode: Int, flags: UInt64, isAutorepeat: Bool = false, at time: TimeInterval,
        insideSecureInput: Bool = false, timestamp: UInt64 = 0
    ) -> Result {
        guard let route else { return Result(decision: .pass) }
        if route.key == .capsLock, keyCode == kVK_CapsLock, type == .flagsChanged {
            cancelQuickPress()
            return Result(decision: .pass, effect: .unmappedCapsLock)
        }
        guard keyCode == route.tapKeyCode else {
            guard isHeld(in: flags) else {
                if isActive { reset() }
                return Result(decision: .pass)
            }
            if type == .keyDown || type == .flagsChanged { used = true }
            return Result(decision: .rewrite(flags: removingSourceFlags(from: flags) | hyperFlags))
        }
        if let modifier = route.modifier {
            guard type == .flagsChanged else { return Result(decision: .pass) }
            return transition(
                isDown: modifier.isHeld(in: flags), flags: removingSourceFlags(from: flags), at: time,
                insideSecureInput: insideSecureInput, timestamp: timestamp)
        }
        guard type == .keyDown || type == .keyUp else { return Result(decision: .pass) }
        guard !isAutorepeat else { return Result(decision: .suppress) }
        let flags = removingSourceFlags(from: flags) & ~CGEventFlags.maskSecondaryFn.rawValue
        return transition(
            isDown: type == .keyDown, flags: flags, at: time, insideSecureInput: insideSecureInput,
            timestamp: timestamp)
    }

    private mutating func transition(
        isDown: Bool, flags: UInt64, at time: TimeInterval, insideSecureInput: Bool, timestamp: UInt64
    ) -> Result {
        let command = Int64(kVK_Command)
        if isDown {
            if !isActive {
                isActive = true
                downAt = time
                // Secure Input hides the other keys, so such a press never counts as unused.
                used = insideSecureInput
            }
            return Result(
                decision: .rewrite(flags: flags | hyperFlags, keyCode: command, asFlagsChanged: true))
        }
        // A stray F18 release ends nothing, but a modifier's release always clears the chord.
        guard isActive || route?.modifier != nil else { return Result(decision: .suppress) }
        var effect: Effect?
        if !used, route?.key.hasOriginalFunction == true, let downAt {
            let duration = time - downAt
            if forwarded == nil {
                effect = .unusedPress(heldFor: duration)
            } else if let physical = forwarded?.confirm(.quartz, timestamp: timestamp, duration: duration) {
                effect = .unusedPress(heldFor: physical)
            }
        }
        endHold()
        return Result(
            decision: .rewrite(flags: flags, keyCode: command, asFlagsChanged: true), effect: effect)
    }
}
