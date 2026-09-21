import Foundation

/// Recognizes physical Globe/fn taps, without treating an F-key's fn flag as Globe.
struct GlobeTapDetector {
    static let resolutionWindow: Duration = .seconds(
        DoubleTapDetector.maxGap + DoubleTapDetector.maxHold + 0.02)

    enum Gesture: Equatable {
        case single
        case double
    }

    private var press: (startedAt: TimeInterval, isSecond: Bool)?
    private var pendingReleaseAt: TimeInterval?

    mutating func handle(
        isGlobeKey: Bool, functionDown: Bool, hasOtherModifiers: Bool, at now: TimeInterval
    ) -> Gesture? {
        guard isGlobeKey, !hasOtherModifiers else {
            cancel()
            return nil
        }
        if functionDown {
            guard press == nil else { return nil }
            let isSecond =
                pendingReleaseAt.map {
                    now >= $0 && now - $0 <= DoubleTapDetector.maxGap
                } ?? false
            press = (now, isSecond)
            pendingReleaseAt = nil
            return nil
        }
        guard let press else { return nil }
        self.press = nil
        guard now >= press.startedAt, now - press.startedAt <= DoubleTapDetector.maxHold else {
            return nil
        }
        if press.isSecond { return .double }
        pendingReleaseAt = now
        return .single
    }

    mutating func cancel() {
        press = nil
        pendingReleaseAt = nil
    }
}
