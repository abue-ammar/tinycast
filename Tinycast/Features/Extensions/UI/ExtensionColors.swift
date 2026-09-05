import SwiftUI

/// Here, not in `Theme`: a third-party screen may never force a change on a launcher one.
enum ExtensionColors {
    /// The Settings card's own surface, so a form field is the same material as the app's.
    static let fieldFill = Theme.Colors.ramp(dark: 0.05, light: 0.04)
    /// The system accent, as every other focused control in the app draws it.
    static let fieldFocusStroke = Color.accentColor
    static let fieldStroke = Theme.Colors.ramp(dark: 0.10, light: 0.10)
    static let tagFill = Theme.Colors.ramp(dark: 0.05, light: 0.05)
    static let tagSelectedStroke = Theme.Colors.ramp(dark: 0.30, light: 0.26)
    /// A checkbox's own edge, brighter than a field's: it is the control, not a container.
    static let checkboxStroke = Theme.Colors.ramp(dark: 0.26, light: 0.30)
    /// Under the pointer, matching the lift every other hoverable row in the app has.
    static let fieldHoverFill = Theme.Colors.ramp(dark: 0.08, light: 0.07)
    static let fieldHoverStroke = Theme.Colors.ramp(dark: 0.18, light: 0.18)
    /// Fainter than a list row, since a grid tiles many of them.
    static let gridItemFill = Theme.Colors.ramp(dark: 0.03, light: 0.035)
    static let detailCardFill = Theme.Colors.ramp(dark: 0.05, light: 0.04)
}
