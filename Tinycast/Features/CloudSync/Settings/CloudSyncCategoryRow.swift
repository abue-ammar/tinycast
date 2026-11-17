import SwiftUI

struct CloudSyncCategoryRow: View {
    let category: SyncCategory
    @Binding var isIncluded: Bool
    let counts: CloudSyncCoordinator.Counts?
    /// Counts differ mid-sync as a matter of course; only a settled difference is worth a warning.
    let isSettled: Bool

    var body: some View {
        LabeledContent {
            HStack(spacing: Theme.Spacing.sm) {
                if isIncluded, let counts {
                    Text("\(counts.local) on this Mac · \(counts.cloud) in iCloud")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if isSettled, counts.local != counts.cloud {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help("Some items haven't synced yet.")
                    }
                }
                if let detail = category.detail {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                        .help(detail)
                        .accessibilityLabel(detail)
                }
            }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Toggle(category.title, isOn: $isIncluded)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                Label(category.title, systemImage: category.symbol)
            }
        }
    }
}
