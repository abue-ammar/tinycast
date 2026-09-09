import SwiftUI

/// The clipboard header's type filter control: it states the active filter and toggles its menu.
struct ClipboardFilterButton: View {
    @Environment(\.locale) private var localizationLocale
    let filter: ClipboardFilter
    let isOpen: Bool
    let action: () -> Void

    var body: some View {
        HeaderMenuButton(
            title: String(localized: String.LocalizationValue(filter.title), bundle: .appLanguage),
            systemImage: filter.systemImage,
            isOpen: isOpen,
            help: String(localized: "Filter by type  ⌘P", bundle: .appLanguage),
            action: action)
    }
}
