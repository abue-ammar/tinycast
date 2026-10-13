import Foundation

struct DoubleTapDetector {
    /// Longest a press may last and still be a tap; matches `HyperKeyTap.quickPressWindow`.
    static let maxHold: TimeInterval = 0.25
    /// Longest gap between the first tap's release and the second tap's press.
    static let maxGap: TimeInterval = 0.30

    enum Input: Sendable {
        /// Which of the four eligible modifiers are now held, and whether `fn` is down too.
        case modifiers(Set<DoubleTapModifier>, hasOtherModifiers: Bool)
        /// A key press or mouse click, which turns the press in flight into a chord.
        case otherInput
    }

    private var held: Set<DoubleTapModifier> = []
    private var press: (modifier: DoubleTapModifier, startedAt: TimeInterval)?
    private var pendingTap: (modifier: DoubleTapModifier, releasedAt: TimeInterval)?

    /// The modifier whose double-tap completed, fired on the second release, never the press.
    mutating func handle(_ input: Input, at now: TimeInterval) -> DoubleTapModifier? {
        switch input {
        case .otherInput:
            invalidate()
            return nil
        case .modifiers(let modifiers, let hasOtherModifiers):
            return handle(modifiers, hasOtherModifiers: hasOtherModifiers, at: now)
        }
    }

    mutating func reset() {
        held = []
        invalidate()
    }

    private mutating func handle(
        _ modifiers: Set<DoubleTapModifier>, hasOtherModifiers: Bool, at now: TimeInterval
    ) -> DoubleTapModifier? {
        let previous = held
        held = modifiers

        guard !hasOtherModifiers else {
            invalidate()
            return nil
        }
        if modifiers.isEmpty { return completeTap(at: now) }

        // A tap begins only from nothing held, so an unwinding chord isn't a fresh press.
        guard previous.isEmpty, modifiers.count == 1, let modifier = modifiers.first else {
            invalidate()
            return nil
        }
        press = (modifier, now)
        return nil
    }

    private mutating func completeTap(at now: TimeInterval) -> DoubleTapModifier? {
        guard let press, now - press.startedAt <= Self.maxHold else {
            invalidate()
            return nil
        }
        self.press = nil

        guard let pending = pendingTap, pending.modifier == press.modifier,
            press.startedAt - pending.releasedAt <= Self.maxGap
        else {
            pendingTap = (press.modifier, now)
            return nil
        }
        pendingTap = nil
        return press.modifier
    }

    private mutating func invalidate() {
        press = nil
        pendingTap = nil
    }
}
