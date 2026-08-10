import SwiftUI

struct FileSearchList: View {
    let results: [FileSearchResult]
    let selectedID: FileSearchResult.ID?
    let scroll: ScrollIntent
    let onActivate: (FileSearchResult) -> Void
    let onActions: (FileSearchResult) -> Void

    private var firstRowSelected: Bool {
        selectedID != nil && selectedID == results.first?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    SectionHeader(title: "Results", isFirst: true)
                    ForEach(results) { result in
                        FileSearchRow(result: result, selected: result.id == selectedID)
                            .contentShape(Rectangle())
                            .onTapGesture { onActivate(result) }
                            .onRightClick { onActions(result) }
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .pinOriginOnInsetSettle(scroll, proxy: proxy)
            .onChange(of: scroll) { _, scroll in
                switch scroll.kind {
                case .top:
                    proxy.scrollToOrigin()
                case .follow:
                    if firstRowSelected {
                        proxy.scrollToOrigin()
                    } else if let selectedID {
                        proxy.reveal(selectedID)
                    }
                }
            }
        }
    }
}

private struct FileSearchRow: View {
    let result: FileSearchResult
    let selected: Bool
    @State private var image: NSImage?
    @State private var hovered = false

    init(result: FileSearchResult, selected: Bool) {
        self.result = result
        self.selected = selected
        _image = State(initialValue: IconCache.cachedFitted(forFile: result.id))
    }

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Group {
                if let image {
                    Image(nsImage: image).resizable()
                } else {
                    RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                }
            }
            .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
            Text(result.name)
                .font(Theme.Typography.rowTitle)
                .lineLimit(1)
            Spacer(minLength: Theme.Spacing.md)
            Text(result.parentPath)
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(result.name)
        .accessibilityValue(result.parentPath)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .task(id: result.id) {
            guard image == nil else { return }
            image = await IconCache.loadFittedAsync(forFile: result.id)
        }
    }
}
