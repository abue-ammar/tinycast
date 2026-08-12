import SwiftUI

/// The "make it look native" control in Settings › Extensions: shows what an extension currently draws
/// in the launcher, and opens a picker to replace it with a curated SF Symbol on a tinted tile.
struct ExtensionAppearanceRow: View {
    let installed: InstalledExtension
    @Environment(AppCore.self) private var core
    @State private var picking = false

    /// Read from the store, not the manager: picking publishes from there, so the preview and the
    /// open popover both observe *it*.
    private var appearance: ExtensionAppearance? {
        core.extensions.appearances.appearance(for: installed.manifest.name)
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            preview
            VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                Text("Launcher icon").font(.body)
                Text(
                    appearance == nil
                        ? "Using the icon this extension ships."
                        : "Replaced with a Tinycast icon."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: Theme.Spacing.xl)
            if appearance != nil {
                Button("Use Original") {
                    core.extensions.setAppearance(nil, for: installed.manifest.name)
                }
            }
            Button("Choose…") { picking = true }
                .popover(isPresented: $picking, arrowEdge: .bottom) {
                    ExtensionAppearancePicker(
                        current: appearance ?? .fallback,
                        onPick: { core.extensions.setAppearance($0, for: installed.manifest.name) })
                }
        }
    }

    /// Exactly what the launcher row will draw — the shipped image, or the chosen tile.
    @ViewBuilder
    private var preview: some View {
        if let appearance {
            SymbolTile(symbol: appearance.symbol, tint: appearance.tint, side: 26)
        } else {
            ExtensionIconView(
                resolved: installed.iconPath.map { ExtensionImage.Resolved(source: .file($0)) },
                size: 26)
        }
    }
}

/// Colour swatches, a category menu and a searchable grid over every symbol the system ships. Changes
/// apply immediately — the launcher is the real preview, so an OK/Cancel dance over two properties
/// isn't worth it.
private struct ExtensionAppearancePicker: View {
    let current: ExtensionAppearance
    let onPick: (ExtensionAppearance) -> Void

    /// Starts on the curated set and swaps in the system catalog once it's parsed (~700 KB of plists,
    /// so it loads off the main actor rather than stalling the popover's first frame).
    @State private var catalog = SymbolCatalog.fallback
    @State private var category = SymbolCategory.suggested
    @State private var query = ""

    private let swatches = Array(repeating: GridItem(.fixed(22), spacing: 8), count: 9)
    private let icons = Array(repeating: GridItem(.fixed(34), spacing: 4), count: 10)

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            LazyVGrid(columns: swatches, spacing: 8) {
                ForEach(ExtensionTint.allCases) { tint in
                    Button {
                        onPick(ExtensionAppearance(symbol: current.symbol, tint: tint))
                    } label: {
                        Circle()
                            .fill(tint.color.gradient)
                            .frame(width: 20, height: 20)
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
                TextField("Search symbols…", text: $query)
                    .textFieldStyle(.plain)
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
                    .frame(width: 396, height: 240)
            } else {
                ScrollView {
                    LazyVGrid(columns: icons, spacing: 4) {
                        ForEach(results, id: \.self) { symbol in
                            Button {
                                onPick(ExtensionAppearance(symbol: symbol, tint: current.tint))
                            } label: {
                                SymbolTile(symbol: symbol, tint: current.tint, side: 30)
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
                    .padding(.horizontal, 2)
                }
                .frame(width: 396, height: 240)
            }

            Text(footnote(results.count))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(Theme.Spacing.xl)
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
private struct SymbolTile: View {
    let symbol: String
    let tint: ExtensionTint
    let side: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: side * 0.23, style: .continuous)
            .fill(tint.color)
            .frame(width: side, height: side)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: side * 0.46, weight: .medium))
                    .foregroundStyle(.white)
            )
    }
}
