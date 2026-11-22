import SwiftUI

struct CloudSyncInfoRow: View {
    let title: String
    let symbol: String
    let tint: IconTint
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
            Label {
                Text(title)
            } icon: {
                SettingsSymbolTile(symbol: symbol, tint: tint)
            }
        }
    }
}
