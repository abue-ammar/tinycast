import SwiftUI

struct WindowSwitchScreen: PaletteScreen {
    let session: WindowSwitchSession
    let core: AppCore

    var rows: [WindowSwitchEntry] { session.filtered }

    var primaryActionTitle: String { "Switch to Window" }

    func hasActions(at selection: Int) -> Bool { false }

    func activate(at selection: Int) {
        guard rows.indices.contains(selection) else { return }
        core.windowSwitchCoordinator.activate(rows[selection])
    }

    func secondary(at selection: Int) -> Bool { false }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        if rows.isEmpty {
            EmptyResults(text: session.snapshot.isEmpty ? "No open windows" : "No windows found")
        } else {
            WindowSwitchList(
                entries: rows,
                selectedID: rows.indices.contains(selection) ? rows[selection].id : nil,
                scroll: scroll,
                onActivate: { core.windowSwitchCoordinator.activate($0) })
        }
    }
}
