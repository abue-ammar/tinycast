import SwiftUI

struct RoomPickerList: View {
    @Environment(\.metrics) private var metrics
    let rows: [RoomPickerRow]
    /// Room order; a member's place is its index plus one.
    let picked: [RoomSession.Pick]
    let selectedID: String?
    let scroll: ScrollIntent
    let onActivate: (RoomPickerRow) -> Void

    private var firstRowSelected: Bool { selectedID != nil && selectedID == rows.first?.id }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        RoomPickerRowView(
                            row: row, place: picked.firstIndex(of: row.pick).map { $0 + 1 },
                            selected: row.id == selectedID
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

private struct RoomPickerRowView: View {
    @Environment(\.metrics) private var metrics
    let row: RoomPickerRow
    /// Its place in the room, 1 being the main window; nil when it is not in the room.
    let place: Int?
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    private var title: String {
        switch row {
        case .window(let window):
            window.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? window.appName : window.title
        case .app(let app):
            app.name
        }
    }

    private var trailing: String {
        switch row {
        case .window(let window):
            if window.isAppHidden { return "\(window.appName) · Hidden" }
            if window.isMinimized { return "\(window.appName) · Minimized" }
            return window.appName
        case .app:
            return "App · Opens with the room"
        }
    }

    private var appURL: URL? {
        switch row {
        case .window(let window): window.appURL
        case .app(let app): app.url
        }
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            badge
            Group {
                if let appURL {
                    EntryIconView(source: .file(stamp: FileIconStamp.value(for: appURL)), fileURL: appURL)
                } else {
                    EntryIconView(source: .symbol("macwindow"))
                }
            }
            .frame(width: metrics.size.rowIcon, height: metrics.size.rowIcon)
            Text(title)
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: metrics.spacing.md)
            Text(trailing)
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous).fill(fill)
        )
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(place.map { "\(trailing), number \($0) in the room" } ?? trailing)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The member's place in the room, or an empty ring where it could go.
    private var badge: some View {
        ZStack {
            Circle()
                .strokeBorder(place == nil ? Theme.Colors.cardStroke : .clear, lineWidth: 1)
                .background(Circle().fill(place == nil ? .clear : Theme.Colors.roomCardStroke))
            if let place {
                Text("\(place)")
                    .font(metrics.typography.rowTrailing.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: metrics.size.rowIcon, height: metrics.size.rowIcon)
    }
}
