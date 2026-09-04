import SwiftUI

/// Here, not in `Theme`: a third-party screen may never force a change on a launcher one.
enum ExtensionColors {
    static let fieldFill = Theme.Colors.ramp(dark: 0.045, light: 0.05)
    static let fieldFocusStroke = Theme.Colors.ramp(dark: 0.28, light: 0.24)
    static let fieldStroke = Theme.Colors.ramp(dark: 0.07, light: 0.10)
    static let tagFill = Theme.Colors.ramp(dark: 0.05, light: 0.05)
    static let tagSelectedStroke = Theme.Colors.ramp(dark: 0.30, light: 0.26)
    /// A picker popover reads as a surface above the form, so it is lighter than a field.
    static let popoverFill = Theme.Colors.adaptive(
        dark: .srgbInk(0.16, alpha: 1), light: .srgbInk(0.98, alpha: 1))
    static let popoverStroke = Theme.Colors.ramp(dark: 0.12, light: 0.12)
    /// A checkbox's own edge, brighter than a field's: it is the whole control, not a container.
    static let checkboxStroke = Theme.Colors.ramp(dark: 0.26, light: 0.30)
    /// Under the pointer: a touch brighter, the way every other hoverable row in the app lifts.
    static let fieldHoverFill = Theme.Colors.ramp(dark: 0.07, light: 0.07)
    static let fieldHoverStroke = Theme.Colors.ramp(dark: 0.16, light: 0.18)
    /// Fainter than a list row, since a grid tiles many of them.
    static let gridItemFill = Theme.Colors.ramp(dark: 0.03, light: 0.035)
    static let detailCardFill = Theme.Colors.ramp(dark: 0.05, light: 0.04)
}
