import SwiftUI

struct CustomCommandList: View {
    @Environment(\.metrics) private var metrics
    let results: [CustomCommand]
    let selectedID: CustomCommand.ID?
    let scroll: ScrollIntent
    let onSelect: (CustomCommand) -> Void
    let onActivate: () -> Void
    let onActions: (CustomCommand) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results, id: \.id.uuidString) { command in
                        Row(command: command, selected: command.id == selectedID)
                            .selectionFrame(command.id == selectedID)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(command) }
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded {
                                    onSelect(command)
                                    onActivate()
                                }
                            )
                            .onRightClick { onActions(command) }
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.top, metrics.spacing.xs)
                .padding(.bottom, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll, row: selectedID?.uuidString,
                atOrigin: selectedID != nil && selectedID == results.first?.id, proxy: proxy)
        }
    }

    private struct Row: View {
        @Environment(\.metrics) private var metrics
        @Environment(HotKeyManager.self) private var hotKeys
        let command: CustomCommand
        let selected: Bool
        @State private var hovered = false

        private var fill: Color {
            if selected { return Theme.Colors.selection }
            return hovered ? Theme.Colors.rowHover : .clear
        }

        var body: some View {
            IconCache.observeStyle()
            return HStack(spacing: metrics.spacing.lg) {
                Image(nsImage: IconCache.symbolIcon(named: command.symbol))
                    .resizable()
                    .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
                Text(command.name).font(metrics.typography.rowTitle).lineLimit(1)
                Spacer(minLength: metrics.spacing.sm)
                if !command.showsInRootSearch {
                    SymbolImage(name: "eye.slash", size: metrics.size.menuIcon)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .accessibilityLabel("Hidden from root search")
                }
                if let keycaps = hotKeys.binding(for: .customCommand(id: command.id))?.keycaps {
                    HStack(spacing: metrics.spacing.xxs) {
                        ForEach(Array(keycaps.enumerated()), id: \.offset) { _, cap in
                            KeyCapChip(text: cap, style: .outline)
                        }
                    }
                }
            }
            .padding(.horizontal, metrics.spacing.md)
            .padding(.vertical, metrics.spacing.sm)
            .background(RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous).fill(fill))
            .armedHover($hovered)
        }
    }
}
