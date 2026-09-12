import SwiftUI

struct MenuSearchScreen: PaletteScreen {
    let session: MenuSearchSession
    let core: AppCore
    let vm: PaletteState
    let openActions: () -> Void

    var rows: [MenuSearchItem] { session.filtered }

    var primaryActionTitle: String { "Activate Menu Item" }

    func hasActions(at selection: Int) -> Bool { false }

    private func item(at selection: Int) -> MenuSearchItem? {
        rows.indices.contains(selection) ? rows[selection] : nil
    }

    func activate(at selection: Int) {
        guard let item = item(at: selection) else { return }
        core.menuSearchCoordinator.activate(item)
    }

    func secondary(at selection: Int) -> Bool { false }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        switch session.target {
        case .searchable(let name):
            if session.state == .reading {
                EmptyResults(text: "Reading menu…")
            } else if rows.isEmpty {
                EmptyResults(text: "No menu items found in \(name)")
            } else {
                MenuSearchList(
                    items: rows, targetName: name, isSearching: session.isSearching,
                    iconURL: core.menuSearchCoordinator.frozenIconURL,
                    iconStamp: core.menuSearchCoordinator.frozenIconStamp,
                    selectedID: rows.indices.contains(selection) ? rows[selection].id : nil,
                    scroll: scroll,
                    onActivate: { core.menuSearchCoordinator.activate($0) })
            }
        case .excluded(let name):
            EmptyResults(text: "Menu search is turned off for \(name)")
        case .selfTarget:
            EmptyResults(text: "Tinycast has no menu to search")
        case .menuLess(let name):
            EmptyResults(text: "\(name) has no menu bar to search")
        case .noApplication:
            EmptyResults(text: "No application to search")
        }
    }
}
