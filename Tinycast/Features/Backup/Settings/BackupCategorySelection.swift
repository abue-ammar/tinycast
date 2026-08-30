import SwiftUI

/// A sibling of `RaycastImportSelection`, not a generalisation: only this greys absent rows.
struct BackupCategorySelection: View {
    @Binding var selection: Set<BackupCategory>
    /// Categories the file actually holds, with how much. nil means everything is offered.
    var available: [BackupCategory: Int]?

    private static let columns = Array(
        repeating: GridItem(.flexible(), spacing: Theme.Spacing.md, alignment: .leading), count: 2)

    private var offered: [BackupCategory] {
        guard let available else { return BackupCategory.allCases }
        return BackupCategory.allCases.filter { available[$0] != nil }
    }

    private func included(_ category: BackupCategory) -> Binding<Bool> {
        Binding(
            get: { selection.contains(category) },
            set: { isOn in
                if isOn { selection.insert(category) } else { selection.remove(category) }
            })
    }

    private func subtitle(_ category: BackupCategory) -> String? {
        guard let noun = category.descriptor.countNoun, let count = available?[category] else {
            return nil
        }
        return "\(count) \(noun)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(offered) { category in
                    Toggle(isOn: included(category)) {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: category.descriptor.symbol)
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text(category.descriptor.label).lineLimit(1)
                            if let subtitle = subtitle(category) {
                                Text(subtitle)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            Button(selection.isEmpty ? "Select All" : "Deselect All") {
                selection = selection.isEmpty ? Set(offered) : []
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
