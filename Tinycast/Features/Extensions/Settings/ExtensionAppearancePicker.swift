import SwiftUI

/// A searchable symbol grid. Changes apply at once: the launcher is the real preview.
struct ExtensionAppearancePicker: View {
    let current: ExtensionAppearance
    /// Whether it is re-skinned, the only time resetting means anything.
    let isCustom: Bool
    let onPick: (ExtensionAppearance) -> Void
    let onReset: () -> Void

    /// The curated set first: ~700 KB of plists would stall the popover's first frame.
    @State private var catalog = SymbolCatalog.fallback
    @State private var category = SymbolCategory.suggested
    @State private var query = ""

    /// One column system from the grid, so every row shares its edges rather than finding its own.
    private enum Metrics {
        static let tile: CGFloat = 30
        static let glyph: CGFloat = 15
        static let columns = 10
        static let gap: CGFloat = 8
        static let inset: CGFloat = Theme.Spacing.xl
        /// Whole rows on show, plus half a tile of the next as a deliberate scroll hint.
        static let visibleRows = 6

        static var contentWidth: CGFloat {
            CGFloat(columns) * tile + CGFloat(columns - 1) * gap
        }
        static var popoverWidth: CGFloat { contentWidth + inset * 2 }
        static var gridHeight: CGFloat {
            CGFloat(visibleRows) * (tile + gap) - gap + tile / 2
        }
    }

    private let icons = Array(
        repeating: GridItem(.fixed(Metrics.tile), spacing: Metrics.gap), count: Metrics.columns)

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("", text: $query, prompt: Text("Search symbols…"))
                    .textFieldStyle(.plain)
                    .labelsHidden()
                    .pointerStyle(.horizontalText)
                Picker("", selection: $category) {
                    ForEach(catalog.categories) { item in
                        Text(item.title).tag(item)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            let results = catalog.search(query, in: category)
            if results.isEmpty {
                Text("No symbols match \u{201C}\(query)\u{201D}.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    // Whole rows: a half one clipped by the footer reads as a rendering bug.
                    .frame(width: Metrics.contentWidth, height: Metrics.gridHeight)
            } else {
                ScrollView {
                    // Leading: a fixed-column `LazyVGrid` centres itself in spare width otherwise.
                    LazyVGrid(columns: icons, alignment: .leading, spacing: Metrics.gap) {
                        ForEach(results, id: \.self) { symbol in
                            Button {
                                onPick(ExtensionAppearance(symbol: symbol))
                            } label: {
                                SymbolImage(name: symbol, size: Metrics.glyph, monochrome: true)
                                    .frame(width: Metrics.tile, height: Metrics.tile)
                                    .background(
                                        RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                                            .fill(symbol == current.symbol ? Theme.Colors.selection : .clear)
                                    )
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(symbol)
                        }
                    }
                    .frame(width: Metrics.contentWidth, alignment: .leading)
                    .hideNativeScrollers()
                }
                .overflowFade()
                .thinScrollbar()
                // The column's width, never the popover's, or the grid overhangs the shared inset.
                .frame(width: Metrics.contentWidth, height: Metrics.gridHeight)
            }

            HStack {
                Text(footnote(results.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Use Original Icon", action: onReset)
                    .disabled(!isCustom)
                    .help("Go back to the icon the extension ships.")
            }
        }
        .padding(Metrics.inset)
        .frame(width: Metrics.popoverWidth)
        .task {
            // Only the fallback has a single category; don't re-read the real catalog.
            guard catalog.categories.count == 1 else { return }
            catalog = await Task.detached(priority: .userInitiated) { SymbolCatalog.load() }.value
        }
    }

    private func footnote(_ count: Int) -> String {
        query.isEmpty
            ? String(localized: "\(count) symbols in \(category.title)")
            : String(localized: "\(count) symbols matching")
    }
}

/// The launcher's tile for an override, restated here because an extension's views stay its own.
struct SymbolTile: View {
    let symbol: String
    let side: CGFloat

    /// Marks the system has no symbol for draw as templates, so they take the ink like a symbol.
    private var glyph: Image {
        SymbolCatalog.isBundled(symbol)
            ? Image(symbol).renderingMode(.template)
            : Image(systemName: symbol)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: side * IconCache.appIconCornerRatio, style: .continuous)
        glyph
            .resizable()
            .scaledToFit()
            .fontWeight(.semibold)
            .fontDesign(.rounded)
            .foregroundStyle(.white)
            .frame(width: side * Theme.IconTile.glyphRatio, height: side * Theme.IconTile.glyphRatio)
            .frame(width: side, height: side)
            .background(Theme.IconTile.fill(SettingsTab.extensions.tint), in: shape)
            .overlay {
                shape.strokeBorder(Theme.IconTile.edgeLight, lineWidth: side * Theme.IconTile.edgeLightRatio)
            }
            .environment(\.colorScheme, .light)
    }
}
