import SwiftUI

struct CloudSyncInfoRow: View {
    let title: String
    let symbol: String
    let detail: String?

    var body: some View {
        LabeledContent {
            if let detail {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .help(detail)
                    .accessibilityLabel(detail)
            }
        } label: {
            Label(title, systemImage: symbol)
        }
    }
}
