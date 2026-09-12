import SwiftUI

/// The clipboard header's type filter control: it states the active filter and toggles its menu.
struct ClipboardFilterButton: View {
    let filter: ClipboardFilter
    let isOpen: Bool
    let action: () -> Void

    var body: some View {
        HeaderMenuButton(
            title: filter.title,
            systemImage: filter.systemImage,
            isOpen: isOpen,
            help: "Filter by type  ⌘P",
            action: action)
    }
}
