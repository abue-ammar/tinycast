import SwiftUI

/// The form shown before a quicklink with placeholders opens.
///
/// The palette's own search field is the input for whichever argument is current, so this view only
/// draws what has been answered and what is left — and, for an argument with `options=`, the choices
/// as ordinary selectable rows so the flat selection index behaves exactly as it does in every other
/// list.
struct QuicklinkArgumentsView: View {
    let options: [String]
    let selection: Int
    let scroll: ScrollIntent
    let onSelect: (Int) -> Void
    let onActivate: () -> Void

    @EnvironmentObject private var session: QuicklinkArgumentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summary
            if options.isEmpty {
                Spacer(minLength: 0)
            } else {
                optionList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if let name = session.quicklinkName {
                Text(name)
                    .font(Theme.Typography.rowTitle.weight(.semibold))
            }
            ForEach(Array(session.progress.enumerated()), id: \.offset) { _, argument in
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: argument.value == nil ? "circle" : "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(
                            argument.value == nil
                                ? Theme.Colors.textTertiary : Theme.Colors.success)
                    Text(argument.name)
                        .font(Theme.Typography.rowTrailing)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    if let value = argument.value {
                        Text(value.isEmpty ? "—" : value)
                            .font(Theme.Typography.rowTrailing)
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md * 2)
        .padding(.top, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.lg)
    }

    private var optionList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    SectionHeader(title: "Choices", isFirst: true)
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        OptionRow(title: option, selected: index == selection)
                            .id(String(index))
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(index) }
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded {
                                    onSelect(index)
                                    onActivate()
                                }
                            )
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .pinOriginOnInsetSettle(scroll, proxy: proxy)
            .onChange(of: scroll) { _, scroll in
                switch scroll.kind {
                case .top: proxy.scrollToOrigin()
                case .follow: proxy.reveal(String(selection))
                }
            }
        }
    }
}

private struct OptionRow: View {
    let title: String
    let selected: Bool
    @State private var hovered = false

    /// Selection wins over hover when a row is both; otherwise hover shows its fainter layer.
    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Text(title)
                .font(Theme.Typography.rowTitle)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
    }
}
