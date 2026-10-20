import Foundation

/// Which windows a switch offers, pure so the rule is testable without Accessibility.
enum WindowSwitchPolicy {
    /// A minimized window reports `AXDialog`, and a sheet cannot minimize: the button tells them apart.
    static func isSwitchable(
        isStandardWindow: Bool, isMinimized: Bool, canMinimize: @autoclosure () -> Bool
    ) -> Bool {
        isStandardWindow || (isMinimized && canMinimize())
    }
}
