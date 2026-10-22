import Foundation

/// Which windows a switch offers, pure so the rule is testable without Accessibility.
enum WindowSwitchPolicy {
    /// Some apps relabel a minimized window `AXDialog`; the minimize button keeps sheets out.
    static func isSwitchable(
        isStandardWindow: Bool, isMinimized: Bool, canMinimize: @autoclosure () -> Bool
    ) -> Bool {
        isStandardWindow || (isMinimized && canMinimize())
    }
}
