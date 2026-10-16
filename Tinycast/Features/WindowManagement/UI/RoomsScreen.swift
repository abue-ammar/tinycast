// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import SwiftUI

/// Switch Room: rooms ranked by the search field, the selected one previewed; ⇥ tries a layout.
struct RoomsScreen: PaletteScreen {
    let coordinator: RoomCoordinator
    let session: RoomSession
    let vm: PaletteState

    var rows: [RoomRow] { coordinator.rows(for: vm.query) }

    var primaryActionTitle: String {
        switch row(at: vm.selection) {
        case .edit: String(localized: "Choose Windows")
        case .create: String(localized: "Create Room")
        case .room, nil: String(localized: "Enter Room")
        }
    }

    private func row(at selection: Int) -> RoomRow? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    private func room(at selection: Int) -> Room? {
        guard case .room(let room) = row(at: selection) else { return nil }
        return room
    }

    func hasActions(at selection: Int) -> Bool { room(at: selection) != nil }

    func activate(at selection: Int) {
        switch row(at: selection) {
        case .room(let room): coordinator.enterRoom(id: room.id)
        case .edit(let room): coordinator.editWindows(of: room)
        case .create(let name): coordinator.createRoom(named: name)
        case nil: break
        }
    }

    func secondary(at selection: Int) -> Bool { false }

    /// The screen owns ⇥ outright: on a room it changes the layout, elsewhere it does nothing.
    func tab(at selection: Int, backwards: Bool) -> Bool {
        if let room = room(at: selection) { coordinator.cycleLayout(of: room, backwards: backwards) }
        return true
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        switch shortcut {
        case .delete:
            guard let room = room(at: selection) else { return false }
            coordinator.deleteRoom(room)
            return true
        case .newItem:
            coordinator.createRoom(named: vm.query.trimmingCharacters(in: .whitespacesAndNewlines))
            return true
        default:
            return false
        }
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let room = room(at: selection) else { return nil }
        return PopoverMenuContent(
            header: room.name,
            items: [
                PopoverMenuItem(
                    title: String(localized: "Enter Room"), systemImage: Room.sfSymbol, shortcut: "↵"
                ) {
                    coordinator.enterRoom(id: room.id)
                },
                PopoverMenuItem(
                    title: String(localized: "Next Layout"), systemImage: "rectangle.3.group",
                    shortcut: "⇥"
                ) {
                    coordinator.cycleLayout(of: room, backwards: false)
                },
                PopoverMenuItem(
                    title: String(localized: "Remember Arrangement"),
                    systemImage: "rectangle.dashed.badge.record",
                    startsSection: true
                ) {
                    coordinator.rememberArrangement(of: room)
                },
                PopoverMenuItem(
                    title: String(localized: "Choose Windows…"), systemImage: "macwindow.badge.plus"
                ) {
                    coordinator.editWindows(of: room)
                },
                PopoverMenuItem(
                    title: String(localized: "Delete Room"), systemImage: "trash", startsSection: true,
                    shortcut: "⌃X",
                    isDestructive: true
                ) {
                    coordinator.deleteRoom(room)
                }
            ])
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        let rows = rows
        let selected = rows.indices.contains(selection) ? rows[selection] : nil
        let previewed = selected.flatMap { row -> Room? in
            guard case .room(let room) = row else { return nil }
            return room
        }
        return AnyView(
            content(rows: rows, selectedID: selected?.id, scroll: scroll)
                // The room's value carries its layout, so Tab's change glides the preview too.
                .onChange(of: PreviewKey(room: previewed, revision: session.revision), initial: true) {
                    coordinator.preview(previewed)
                })
    }

    @ViewBuilder
    private func content(rows: [RoomRow], selectedID: RoomRow.ID?, scroll: ScrollIntent) -> some View {
        if rows.isEmpty {
            EmptyResults(text: String(localized: "Type a name to make your first room"))
        } else {
            RoomsList(
                rows: rows, selectedID: selectedID, scroll: scroll,
                currentRoomID: coordinator.currentRoomID, layout: coordinator.layout(of:),
                onActivate: { row in
                    guard let index = rows.firstIndex(of: row) else { return }
                    activate(at: index)
                })
        }
    }

    private struct PreviewKey: Equatable {
        let room: Room?
        let revision: Int
    }
}
