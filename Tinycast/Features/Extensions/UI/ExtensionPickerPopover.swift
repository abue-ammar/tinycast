import SwiftUI

/// One choice offered by a picker popover.
struct ExtensionPickerItem: Identifiable, Equatable {
    let value: String
    let title: String
    var detail: String?
    var iconValue: RenderValue?
    /// The section this choice was declared under, drawn as a heading above the first of them.
    var section: String?

    var id: String { value }
}

/// The searchable list a form's pickers drop, exactly as Raycast's own forms do.
/// It draws only the panel: the control above keeps the keyboard and owns every key, so the
/// search row here renders the query rather than editing it. A second first responder inside an
/// overlay would take focus off the field and close the list it belongs to.
struct ExtensionPickerPopover: View {
    @Environment(\.isDarkAppearance) private var isDark
    let items: [ExtensionPickerItem]
    let selection: Int
    /// Values already chosen; a single-select picker passes the one it holds.
    let chosen: Set<String>
    let assetsPath: String?
    /// What the search row prompts with; nil draws no search row at all.
    let searchPlaceholder: String?
    let query: String
    let onSelect: (Int) -> Void
    /// Moves the highlight under the pointer, so the mouse and the keyboard share one selection.
    let onHighlight: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let placeholder = searchPlaceholder {
                searchRow(placeholder: placeholder)
            }
            list
        }
        .padding(ExtensionFormMetrics.popoverPadding)
        .frame(width: ExtensionFormMetrics.controlWidth)
        .background(
            RoundedRectangle(
                cornerRadius: ExtensionFormMetrics.popoverCornerRadius, style: .continuous
            )
            .fill(ExtensionColors.popoverFill)
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: ExtensionFormMetrics.popoverCornerRadius, style: .continuous
            )
            .strokeBorder(ExtensionColors.popoverStroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
    }

    /// The typed text plus a drawn caret; the control above is the real first responder.
    private func searchRow(placeholder: String) -> some View {
        HStack(spacing: 1) {
            if query.isEmpty {
                Text(placeholder)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textTertiary)
            } else {
                Text(query)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: ExtensionFormMetrics.popoverSearchHeight)
    }

    @ViewBuilder
    private var list: some View {
        if items.isEmpty {
            Text("No matches")
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.Spacing.md)
                .frame(height: ExtensionFormMetrics.popoverRowHeight, alignment: .leading)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: ExtensionFormMetrics.popoverRowSpacing) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            // A heading above the first row of each section, as Raycast draws them.
                            if let section = item.section, section != sectionBefore(index) {
                                Text(section)
                                    .font(Theme.Typography.sectionHeader)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, Theme.Spacing.md)
                                    .frame(
                                        height: ExtensionFormMetrics.popoverSectionHeaderHeight,
                                        alignment: .leading)
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
                .scrollBounceBehavior(.basedOnSize)
                // `never`, not `hidden`: hidden still lets AppKit claim the scroller's gutter.
                .scrollIndicators(.never)
                .onChange(of: selection) { proxy.scrollTo(selection) }
            }
        }
    }

    /// The section of the row before this one, so only the first of a run draws its heading.
    private func sectionBefore(_ index: Int) -> String? {
        index > 0 ? items[index - 1].section : nil
    }

    /// How many headings the list draws, which the height maths has to count as well as rows.
    private var headerCount: Int {
        items.indices.reduce(into: 0) { total, index in
            guard let section = items[index].section, section != sectionBefore(index) else { return }
            total += 1
        }
    }
}
