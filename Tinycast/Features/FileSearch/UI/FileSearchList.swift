import SwiftUI

struct FileSearchList: View {

    @Environment(\.metrics) private var metrics
    let results: [FileSearchResult]
    let selectedID: FileSearchResult.ID?
    var showsInfoPanel = false
    let scroll: ScrollIntent
    let onSelect: (FileSearchResult) -> Void
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
                        FileSearchRow(
                            result: result,
                            selected: result.id == selectedID,
                            showsInfoPanel: showsInfoPanel
                        )
                        .id(result.id)
                        .selectionFrame(result.id == selectedID)
                        .contentShape(Rectangle())
                        .overlay {
                            RowClickHandle(
                                onSelect: { onSelect(result) },
                                onActivate: { onActivate(result) })
                        }
                        .onRightClick { onActions(result) }
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
                scroll, row: selectedID, atOrigin: firstRowSelected, proxy: proxy)
        }
        .onDisappear {
            IconCache.purgeFitted()
            FilePreviewThumbnail.purgePreviews()
        }
    }
}

private struct FileSearchRow: View {

    @Environment(\.metrics) private var metrics
    let result: FileSearchResult
    let selected: Bool
    let showsInfoPanel: Bool
    @State private var image: NSImage?
    @State private var hovered = false

    init(result: FileSearchResult, selected: Bool, showsInfoPanel: Bool) {
        self.result = result
        self.selected = selected
        self.showsInfoPanel = showsInfoPanel
        _image = State(initialValue: IconCache.cachedFitted(forFile: result.id))
    }

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            Group {
                if let image {
                    Image(nsImage: image).resizable()
                } else {
                    RoundedRectangle(cornerRadius: metrics.radius.thumbnail, style: .continuous)
                        .fill(Theme.Colors.iconPlaceholder)
                }
            }
            .frame(width: metrics.size.rowIcon, height: metrics.size.rowIcon)
            Text(result.name)
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
                .truncationMode(showsInfoPanel ? .tail : .middle)
            Spacer(minLength: showsInfoPanel ? 0 : metrics.spacing.md)
            if !showsInfoPanel {
                Text(result.parentPath)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(result.name)
        .accessibilityValue(result.parentPath)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .task(id: IconRequest(result.id)) {
            if let warm = IconCache.cachedFitted(forFile: result.id) {
                image = warm
                return
            }
            image = await IconCache.loadFittedAsync(forFile: result.id)
        }
    }
}

private struct RowClickHandle: NSViewRepresentable {
    var onSelect: () -> Void
    var onActivate: () -> Void

    func makeNSView(context: Context) -> RowClickView {
        RowClickView()
    }

    func updateNSView(_ nsView: RowClickView, context: Context) {
        nsView.onSelect = onSelect
        nsView.onActivate = onActivate
    }
}

private final class RowClickView: NSView {
    var onSelect: (() -> Void)?
    var onActivate: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        switch NSApp.currentEvent?.type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged: return nil
        default: return super.hitTest(point)
        }
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
        if event.clickCount == 2 {
            onActivate?()
        }
    }
}
