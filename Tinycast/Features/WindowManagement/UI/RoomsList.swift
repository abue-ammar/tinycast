import SwiftUI

struct RoomsList: View {
    @Environment(\.metrics) private var metrics
    let rows: [RoomRow]
    let selectedID: RoomRow.ID?
    let scroll: ScrollIntent
    let currentRoomID: UUID?
    let layout: (Room) -> RoomLayoutKind
    let onActivate: (RoomRow) -> Void

    private var firstRowSelected: Bool { selectedID != nil && selectedID == rows.first?.id }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        RoomRowView(
                            row: row, selected: row.id == selectedID,
                            isCurrent: row.room?.id == currentRoomID,
                            layout: row.room.map(layout)
                        )
                        .selectionFrame(row.id == selectedID)
                        .contentShape(Rectangle())
                        .onTapGesture { onActivate(row) }
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.vertical, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(scroll, row: selectedID, atOrigin: firstRowSelected, proxy: proxy)
        }
    }
}

private struct RoomRowView: View {
    @Environment(\.metrics) private var metrics
    let row: RoomRow
    let selected: Bool
    let isCurrent: Bool
    /// Nil for the rows that make or edit a room rather than enter one.
    let layout: RoomLayoutKind?
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    private var title: String {
        switch row {
        case .room(let room): room.name
        case .edit(let room): "Choose Windows for “\(room.name)”"
        case .create(let name): "Create Room “\(name)”"
        }
    }

    private var subtitle: String {
        switch row {
        case .room(let room):
            let apps = room.windows.map(\.appName).reduce(into: [String]()) { names, name in
                if !names.contains(name) { names.append(name) }
            }
            return ([isCurrent ? "Current" : nil, room.summary] + [apps.joined(separator: ", ")])
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        case .edit, .create:
            return "Pick the open windows that belong in it"
        }
    }

    private var symbol: String {
        switch row {
        case .room: Room.sfSymbol
        case .edit: "macwindow.badge.plus"
        case .create: CommandID.createRoom.sfSymbol
        }
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            EntryIconView(source: .symbol(symbol))
                .frame(width: metrics.size.rowIcon, height: metrics.size.rowIcon)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(metrics.typography.rowTitle)
                    .lineLimit(1)
                Text(subtitle)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: metrics.spacing.md)
            if let layout {
                HStack(spacing: metrics.spacing.sm) {
                    Text(layout.title)
                        .font(metrics.typography.rowTrailing)
                        .foregroundStyle(.secondary)
                    // Tab changes the selected room's layout, so only that row advertises it.
                    if selected { KeyCapChip(text: "⇥", style: .outline) }
                }
            }
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous).fill(fill)
        )
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(layout.map { "\(subtitle), \($0.title) layout" } ?? subtitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension RoomRow {
    fileprivate var room: Room? {
        guard case .room(let room) = self else { return nil }
        return room
    }
}
