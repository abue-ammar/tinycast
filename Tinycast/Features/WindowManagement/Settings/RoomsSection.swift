import SwiftUI

/// The room library, inside the Window Management pane: rooms tile with its gap and its grant.
struct RoomsSection: View {
    @Environment(RoomStore.self) private var store
    @Environment(RoomCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return Section {
            Toggle(isOn: $settings.windowRoomsShowInLauncher) {
                SettingsRowTitle(.windowManagementRooms, "Show rooms in launcher")
            }

            if store.rooms.isEmpty {
                Text("Save a project's windows as a room, then walk into it with one shortcut.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.rooms) { room in
                    RoomSettingsRow(room: room)
                }
            }

            Button {
                coordinator.createRoom()
            } label: {
                SettingsRowTitle(.windowManagementRooms, "New Room")
            }
        } header: {
            SettingsSectionHeader(.windowManagementRooms)
        }
    }
}

/// One room's shortcut, launcher checkbox and actions, shaped like the layout row.
private struct RoomSettingsRow: View {
    let room: Room

    @Environment(RoomCoordinator.self) private var coordinator
    @Environment(VisibilityStore.self) private var visibility

    private var subtitle: String {
        "\(room.summary) · \(coordinator.layout(of: room).title)"
    }

    var body: some View {
        SettingsRow(title: room.name, subtitle: subtitle) {
            SymbolImage(name: Room.sfSymbol, size: 13)
        } trailing: {
            ShortcutRecorder(action: .windowRoom(id: room.id))

            Button {
                coordinator.enterRoom(id: room.id)
            } label: {
                Image(systemName: "play")
            }
            .buttonStyle(.plain)
            .help("Enter this room")
            .accessibilityLabel("Enter \(room.name)")

            Button {
                coordinator.editWindows(of: room)
            } label: {
                Image(systemName: "macwindow.badge.plus")
            }
            .buttonStyle(.plain)
            .help("Choose its windows")
            .accessibilityLabel("Choose windows for \(room.name)")

            Button {
                coordinator.deleteRoom(room)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Theme.Colors.destructive)
            }
            .buttonStyle(.plain)
            .help("Delete")
            .accessibilityLabel("Delete \(room.name)")

            Toggle("", isOn: visibilityBinding)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .launcherVisibilityHelp()
                .accessibilityLabel("Show \(room.name) in launcher")
        }
    }

    private var visibilityBinding: Binding<Bool> {
        Binding(
            get: { visibility.isItemVisible(AppEntry(room)) },
            set: { visibility.setItemVisible($0, for: AppEntry(room)) })
    }
}
