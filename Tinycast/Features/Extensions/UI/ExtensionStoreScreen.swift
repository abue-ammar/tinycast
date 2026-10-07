import SwiftUI

struct ExtensionStoreScreen: PaletteScreen {
    let session: ExtensionStoreSession
    let coordinator: ExtensionStoreCoordinator
    let vm: PaletteState
    let openActions: () -> Void
    let openArgumentOptions: (String) -> Void

    var rows: [ExtensionListing] {
        session.listings
    }

    var primaryActionTitle: String { "Show Details" }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard rows.indices.contains(selection) else { return nil }
        let listing = rows[selection]
        var items = [PopoverMenuItem(title: "Show Details", systemImage: "info.circle", shortcut: "↵") {
            coordinator.details(listing)
        }]
        items += ExtensionStoreActions.items(listing: listing, coordinator: coordinator)
        return PopoverMenuContent(header: listing.title, items: items)
    }

    func activate(at selection: Int) {
        guard rows.indices.contains(selection) else { return }
        coordinator.details(rows[selection])
    }

    func secondary(at selection: Int) -> Bool {
        guard rows.indices.contains(selection) else { return false }
        coordinator.activate(rows[selection])
        return true
    }

    func headerAccessory(at selection: Int, focus: FocusState<String?>.Binding) -> PaletteHeaderAccessory? {
        PaletteHeaderAccessory(
            width: coordinator.metrics.scaled(190), fieldNames: ["storeCategory"], firstIncompleteField: nil,
            optionsMenu: { _ in categories(focus: focus) }, placement: .besideSearchField,
            view: AnyView(ExtensionStoreCategoryButton(
                title: session.installedOnly ? "Installed" : session.category ?? "All Categories",
                onOpen: { openArgumentOptions("storeCategory") })
                .frame(maxWidth: .infinity, alignment: .trailing)))
    }

    private func categories(focus: FocusState<String?>.Binding) -> PopoverMenuContent {
        PopoverMenuContent(items: (["Installed", "All Categories"] + ExtensionStoreResponse.categories).map { category in
            PopoverMenuItem(title: category, systemImage: category == "Installed" ? "checkmark.circle" : "tray") {
                focus.wrappedValue = nil
                vm.focusToken = UUID()
                coordinator.selectCategory(category == "All Categories" ? nil : category)
            }
        })
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(ExtensionStoreListView(
            listings: rows, session: session, coordinator: coordinator,
            selection: selection, scroll: scroll,
            onSelect: { vm.selection = $0 },
            onActivate: { activate(at: $0) },
            onActions: { vm.selection = $0; openActions() }))
    }
}

private struct ExtensionStoreCategoryButton: View {
    let title: String
    let onOpen: () -> Void
    @Environment(\.metrics) private var metrics

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: metrics.spacing.sm) {
                SymbolImage(name: "tray", size: metrics.size.menuIcon)
                Text(title).lineLimit(1)
                SymbolImage(name: "chevron.down", size: metrics.scaled(10))
            }
            .font(metrics.typography.bar)
            .foregroundStyle(Theme.Colors.textSecondary)
        }
        .buttonStyle(.plain)
        .tooltip("Filter by category")
    }
}
