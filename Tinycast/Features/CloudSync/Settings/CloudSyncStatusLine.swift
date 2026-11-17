import SwiftUI

struct CloudSyncStatusLine: View {
    let status: CloudSyncStatus
    let stopReason: CloudSyncStopReason?
    let retry: () -> Void

    var body: some View {
        switch status {
        case .off:
            if let stopReason {
                Label(stopReason.message, systemImage: "exclamationmark.icloud")
                    .foregroundStyle(.secondary)
            }
        case .unavailable(let reason):
            Label(reason.message, systemImage: "icloud.slash")
                .foregroundStyle(.secondary)
        case .syncing(let initial):
            HStack(spacing: Theme.Spacing.sm) {
                ProgressView().controlSize(.small)
                Text(initial ? "Setting up iCloud Sync…" : "Syncing…")
                    .foregroundStyle(.secondary)
            }
        case .upToDate(let date):
            Label {
                if let date {
                    Text("Up to date · last synced \(date, format: .relative(presentation: .named))")
                } else {
                    Text("Up to date")
                }
            } icon: {
                Image(systemName: "checkmark.icloud.fill").foregroundStyle(.green)
            }
            .foregroundStyle(.secondary)
        case .offline(let problem, _):
            LabeledContent {
                Button("Retry", action: retry)
            } label: {
                Label(problem.message, systemImage: "exclamationmark.icloud.fill")
                    .foregroundStyle(.orange)
            }
        case .needsUpdate:
            Label(
                "Another Mac uses a newer Tinycast. Update this one to keep syncing.",
                systemImage: "arrow.down.circle.fill"
            )
            .foregroundStyle(.orange)
        }
    }
}
