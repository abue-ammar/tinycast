// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import SwiftUI

/// One picker row: an open window, or an app that joins the room without one open.
enum RoomPickerRow: Identifiable {
    case window(RoomLiveWindow)
    case app(RoomSession.App)

    var id: String {
        switch self {
        case .window(let window): "window:\(window.handle)"
        case .app(let app): "app:" + app.bundleID
        }
    }

    var pick: RoomSession.Pick {
        switch self {
        case .window(let window): .window(handle: window.handle)
        case .app(let app): .app(app)
        }
    }
}

/// Choose a room's members: the field filters, ↵ adds or removes one, ⌘↵ saves and walks in.
struct RoomPickerScreen: PaletteScreen {
    let coordinator: RoomCoordinator
    let session: RoomSession
    let vm: PaletteState

    var rows: [RoomPickerRow] { coordinator.pickerRows(for: vm.query) }

    var primaryActionTitle: String {
        let rows = rows
        let name = "“\(session.roomName)”"
        guard rows.indices.contains(vm.selection) else { return "Add to \(name)" }
        return session.picked.contains(rows[vm.selection].pick) ? "Remove from \(name)" : "Add to \(name)"
    }

    func activate(at selection: Int) {
        let rows = rows
        guard rows.indices.contains(selection) else { return }
        coordinator.togglePick(rows[selection].pick)
    }

    func secondary(at selection: Int) -> Bool {
        coordinator.savePicked()
        return true
    }

    /// ⇥ would otherwise leave for the launcher and drop everything picked so far.
    func tab(at selection: Int, backwards: Bool) -> Bool { true }

    func actions(at selection: Int) -> PopoverMenuContent? {
        PopoverMenuContent(
            header: session.roomName,
            items: [
                PopoverMenuItem(
                    title: primaryActionTitle, systemImage: "checkmark.circle", shortcut: "↵"
                ) {
                    activate(at: selection)
                },
                PopoverMenuItem(title: "Save Room", systemImage: Room.sfSymbol, shortcut: "⌘↵") {
                    coordinator.savePicked()
                }
            ])
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        let rows = rows
        let selectedID = rows.indices.contains(selection) ? rows[selection].id : nil
        return AnyView(
            Group {
                if rows.isEmpty {
                    EmptyResults(text: emptyText)
                } else {
                    RoomPickerList(
                        rows: rows, picked: session.picked, selectedID: selectedID,
                        scroll: scroll, onActivate: { coordinator.togglePick($0.pick) })
                }
            }
            .onChange(of: session.revision, initial: true) { coordinator.previewPicked() })
    }

    private var emptyText: String {
        guard session.isLoaded else { return "Reading windows…" }
        return vm.query.isEmpty
            ? "No open windows — type an app's name to add it" : "No windows or apps found"
    }
}
