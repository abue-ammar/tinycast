import SwiftUI

/// The results a picker drops, styled as the ⌘K panel; the control above owns the query.
struct ExtensionPickerList: View {
    private var form: ExtensionFormMetrics { ExtensionFormMetrics(scale: metrics.scale) }
    @Environment(\.metrics) private var metrics
    @Environment(\.isDarkAppearance) private var isDark
    /// Read for `hoverHighlightArmed`: a list landing under the pointer must light no row.
    @Environment(PaletteState.self) private var palette
    let items: [ExtensionPickerItem]
    let selection: Int
    /// Values already chosen; a single-select picker passes the one it holds.
    let chosen: Set<String>
    let assetsPath: String?
    /// Fixed, never intrinsic, so the list cannot jitter as its rows change. A form's picker
    /// matches the field above it; a header dropdown hangs off a chip and drops narrower.
    var width: CGFloat?
    let onSelect: (Int) -> Void
    /// Moves the highlight under the pointer, so mouse and keyboard share one selection.
    let onHighlight: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: form.popoverRowSpacing) {
            list
        }
        .padding(metrics.spacing.sm)
        .frame(width: width ?? form.controlWidth)
        .glassEffect(
            .regular, in: RoundedRectangle(cornerRadius: metrics.radius.menuPanel, style: .continuous)
        )
    }

    @ViewBuilder
    private var list: some View {
        if items.isEmpty {
            Text("No matches")
                .font(metrics.typography.menuRow)
                .foregroundStyle(.secondary)
                .padding(.horizontal, metrics.spacing.lg)
                .frame(height: form.popoverRowHeight, alignment: .leading)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: form.popoverRowSpacing) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if let section = item.section, section != sectionBefore(index) {
                                sectionHeader(section)
                            }
                            ExtensionPickerRow(
                                title: item.title,
                                detail: item.detail,
                                icon: ExtensionImage.resolve(
                                    item.iconValue, assetsPath: assetsPath, isDark: isDark),
                                checked: chosen.contains(item.value),
                                selected: index == selection,
                                onActivate: { onSelect(index) }
                            )
                            .id(index)
                            .onHover { if $0, palette.hoverHighlightArmed { onHighlight(index) } }
                        }
                    }
                }
                .frame(
                    height: form.popoverListHeight(
                        rows: items.count, headers: headerCount)
                )
                // Without this a list shorter than the cap rubber-bands against nothing.
                .scrollBounceBehavior(.basedOnSize)
                // `never`, not `hidden`: hidden still lets AppKit claim the scroller's gutter.
                .scrollIndicators(.never)
                .overflowFade()
                .onChange(of: selection, initial: true) { proxy.scrollTo(selection) }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(metrics.typography.sectionHeader)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, metrics.spacing.lg)
            .frame(height: form.popoverSectionHeaderHeight, alignment: .leading)
    }

    /// The section of the row before this one, so only the first of a run draws its heading.
    private func sectionBefore(_ index: Int) -> String? {
        index > 0 ? items[index - 1].section : nil
    }

    /// Headings the list draws, which the height maths counts as well as rows.
    private var headerCount: Int {
        items.indices.reduce(into: 0) { total, index in
            guard let section = items[index].section, section != sectionBefore(index) else { return }
            total += 1
        }
    }
}
