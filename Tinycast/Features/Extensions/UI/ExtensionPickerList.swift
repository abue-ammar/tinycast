import SwiftUI

/// One choice offered by a picker's list.
struct ExtensionPickerItem: Identifiable, Equatable {
    let value: String
    let title: String
    var detail: String?
    var iconValue: RenderValue?
    /// The section this choice was declared under, drawn above the first of them.
    var section: String?

    var id: String { value }
}

/// The results a picker drops, styled as the ⌘K panel; the control above owns the query.
struct ExtensionPickerList: View {
    @Environment(\.isDarkAppearance) private var isDark
    let items: [ExtensionPickerItem]
    let selection: Int
    /// Values already chosen; a single-select picker passes the one it holds.
    let chosen: Set<String>
    let assetsPath: String?
    let onSelect: (Int) -> Void
    /// Moves the highlight under the pointer, so mouse and keyboard share one selection.
    let onHighlight: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ExtensionFormMetrics.popoverRowSpacing) {
            list
        }
        .padding(Theme.Spacing.sm)
        .frame(width: ExtensionFormMetrics.controlWidth)
        .glassEffect(
            .regular, in: RoundedRectangle(cornerRadius: Theme.Radius.menuPanel, style: .continuous)
        )
    }

    @ViewBuilder
    private var list: some View {
        if items.isEmpty {
            Text("No matches")
                .font(Theme.Typography.menuRow)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.Spacing.lg)
                .frame(height: ExtensionFormMetrics.popoverRowHeight, alignment: .leading)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: ExtensionFormMetrics.popoverRowSpacing) {
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
                                onActivate: { onSelect(index) })
                            .id(index)
                            .onHover { if $0 { onHighlight(index) } }
                        }
                    }
                }
                .frame(
                    height: ExtensionFormMetrics.popoverListHeight(
                        rows: items.count, headers: headerCount))
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
            .font(Theme.Typography.sectionHeader)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, Theme.Spacing.lg)
            .frame(height: ExtensionFormMetrics.popoverSectionHeaderHeight, alignment: .leading)
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
