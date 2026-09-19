import AppKit

/// The font families this Mac can draw text with; the system face is this setting's absence.
enum FontCatalog {
    @MainActor
    static func installedFamilies() -> [String] {
        NSFontManager.shared.availableFontFamilies
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// A family the user picked before uninstalling the font must not outvote the system face.
    @MainActor
    static func isInstalled(_ family: String) -> Bool {
        NSFontManager.shared.availableMembers(ofFontFamily: family) != nil
    }
}
