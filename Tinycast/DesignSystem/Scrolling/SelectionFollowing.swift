import SwiftUI

extension View {
    /// Publishes the selected row's frame for `scrollFollowsSelection`; only that row measures.
    func selectionFrame(_ selected: Bool) -> some View {
        overlay {
            if selected {
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: SelectionFrameKey.self, value: geometry.frame(in: .scrollView))
                }
            }
        }
    }

    /// Keeps the keyboard selection in the band between the bars; needs `selectionFrame` on rows.
    func scrollFollowsSelection(
        _ scroll: ScrollIntent, row: String?, atOrigin: Bool, proxy: ScrollViewProxy
    ) -> some View {
        modifier(SelectionFollowing(scroll: scroll, row: row, atOrigin: atOrigin, proxy: proxy))
    }
}

private struct SelectionFrameKey: PreferenceKey {
    static var defaultValue: CGRect? { nil }

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = value ?? nextValue()
    }
}

private struct SelectionFollowing: ViewModifier {
    let scroll: ScrollIntent
    let row: String?
    let atOrigin: Bool
    let proxy: ScrollViewProxy

    @State private var band = Band(insetTop: 0, height: 0)
    @State private var selection: CGRect?
    /// True from a `follow` until the selection is in the band; after that the pointer owns it.
    @State private var following = false

    /// The geometry the rule reads: the band's height, and the inset whose settling moves the rest.
    private struct Band: Equatable {
        var insetTop: CGFloat
        var height: CGFloat
    }

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Band.self) {
                Band(insetTop: $0.contentInsets.top, height: $0.containerSize.height)
            } action: { old, new in
                band = new
                // The inset settles after mount and moves the resting offset, so `top` is restated.
                if scroll.kind == .top, old.insetTop != new.insetTop { proxy.scrollToOrigin() }
                align()
            }
            .onPreferenceChange(SelectionFrameKey.self) { frame in
                selection = frame
                align()
            }
            .onChange(of: scroll) { _, scroll in
                switch scroll.kind {
                case .top:
                    following = false
                    proxy.scrollToOrigin()
                case .follow:
                    following = true
                    align()
                }
            }
    }

    private func align() {
        guard following, let row else { return }
        // Origin, not the row's top, so the first row's section header stays on screen.
        if atOrigin {
            following = false
            return proxy.scrollToOrigin()
        }
        // The lazy stack dropped the selected row: bring it back by id, then re-check its frame.
        guard let selection else {
            return proxy.scrollTo(row, anchor: nil)
        }
        guard
            let edge = SelectionReveal.edge(
                rowTop: selection.minY, rowBottom: selection.maxY, band: band.height)
        else {
            following = false
            return
        }
        proxy.scrollTo(row, anchor: edge == .top ? .top : .bottom)
    }
}
