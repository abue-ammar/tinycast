import SwiftUI

struct ExtensionStoreDetailsScreen: PaletteScreen {
    let session: ExtensionStoreSession
    let coordinator: ExtensionStoreCoordinator

    var rows: [ExtensionListing] { [] }
    var actsWithoutRows: Bool { true }
    var hidesSearchField: Bool { true }
    var primaryActionTitle: String {
        session.detail.map { coordinator.primaryTitle(for: $0) } ?? "Install Extension"
    }

    func hasPrimaryAction(at selection: Int) -> Bool {
        guard let listing = session.detail else { return false }
        return coordinator.canActivate(listing)
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let listing = session.detail else { return nil }
        return PopoverMenuContent(header: listing.title, items: ExtensionStoreActions.items(
            listing: listing, coordinator: coordinator))
    }

    func activate(at selection: Int) {
        guard hasPrimaryAction(at: selection), let listing = session.detail else { return }
        coordinator.activate(listing)
    }

    func secondary(at selection: Int) -> Bool { activate(at: selection); return true }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        guard let listing = session.detail else { return AnyView(EmptyResults(text: "Extension unavailable")) }
        return AnyView(VStack(spacing: 0) {
            if session.detailLoading { ProgressView().controlSize(.small) }
            if let failure = session.detailFailure ?? session.installFailures[listing.name] {
                HStack {
                    Text(failure).font(.caption).foregroundStyle(Theme.Colors.destructive)
                    if session.detailFailure != nil {
                        Button("Retry") { session.showDetails(listing) }
                    }
                }
                .padding(.horizontal)
            }
            ExtensionStoreDetailsView(listing: listing, onOpenURL: coordinator.open)
        })
    }
}
