import SwiftUI

/// Swatches and a searchable symbol grid. Changes apply at once: the launcher is the real preview.
struct ExtensionAppearancePicker: View {
    let current: ExtensionAppearance
    /// Whether the extension is currently re-skinned, which is the only time resetting means anything.
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
        static let columns = 10
        static let gap: CGFloat = 8
        static let inset: CGFloat = Theme.Spacing.xl
        static let swatchesPerRow = 9
        static let swatch: CGFloat = 20
        /// Whole rows on show, plus half a tile of the next as a deliberate scroll hint.
        static let visibleRows = 6

        static var contentWidth: CGFloat {
            CGFloat(columns) * tile + CGFloat(columns - 1) * gap
        }
        static var popoverWidth: CGFloat { contentWidth + inset * 2 }
        static var gridHeight: CGFloat {
            CGFloat(visibleRows) * (tile + gap) - gap + tile / 2
        }
        /// Spread across the same width, so the first and last swatch sit on the grid's edges.
        static var swatchGap: CGFloat {
            (contentWidth - CGFloat(swatchesPerRow) * swatch) / CGFloat(swatchesPerRow - 1)
        }
    }

    private let swatches = Array(
        repeating: GridItem(.fixed(Metrics.swatch), spacing: Metrics.swatchGap),
        count: Metrics.swatchesPerRow)
    private let icons = Array(
        repeating: GridItem(.fixed(Metrics.tile), spacing: Metrics.gap), count: Metrics.columns)

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            LazyVGrid(columns: swatches, alignment: .leading, spacing: Metrics.gap) {
                ForEach(ExtensionTint.allCases) { tint in
                    Button {
                        onPick(ExtensionAppearance(symbol: current.symbol, tint: tint))
                    } label: {
                        Circle()
                            .fill(tint.color.gradient)
                            .frame(width: Metrics.swatch, height: Metrics.swatch)
                            .overlay(
                                Circle().strokeBorder(
                                    .white.opacity(tint == current.tint ? 0.9 : 0), lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(tint.title)
                }
            }

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
                                onPick(ExtensionAppearance(symbol: symbol, tint: current.tint))
                            } label: {
                                SymbolTile(symbol: symbol, tint: current.tint, side: Metrics.tile)
                                    .opacity(symbol == current.symbol ? 1 : 0.55)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .strokeBorder(
                                                .white.opacity(symbol == current.symbol ? 0.9 : 0),
                                                lineWidth: 2)
                                    )
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
            // Only the fallback has a single category; once the real catalog is in, don't re-read it.
            guard catalog.categories.count == 1 else { return }
            catalog = await Task.detached(priority: .userInitiated) { SymbolCatalog.load() }.value
        }
    }

    private func footnote(_ count: Int) -> String {
        let noun = count == 1 ? "symbol" : "symbols"
        return query.isEmpty ? "\(count) \(noun) in \(category.title)" : "\(count) \(noun) matching"
    }
}

/// The launcher's icon tile, drawn in SwiftUI so the picker previews exactly what `IconCache` renders.
struct SymbolTile: View {
    let symbol: String
    let tint: ExtensionTint
    let side: CGFloat

    /// Marks the system has no symbol for; they draw as templates, so they tint like a symbol.
    @ViewBuilder
    private var glyph: some View {
        if SymbolCatalog.isBundled(symbol) {
            Image(symbol)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: side * 0.5, height: side * 0.5)
                .foregroundStyle(.white)
        } else {
            Image(systemName: symbol)
                .font(.system(size: side * 0.46, weight: .medium))
                .foregroundStyle(.white)
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: side * 0.23, style: .continuous)
            .fill(tint.color)
            .frame(width: side, height: side)
            .overlay(glyph)
    }
}
