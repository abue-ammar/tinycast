import SwiftUI

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
