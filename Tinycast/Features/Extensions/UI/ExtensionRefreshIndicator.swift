import SwiftUI

/// Launcher dot for a scheduled extension command. The shared row embeds it but owns nothing of it.
struct ExtensionRefreshIndicator: View {
    let state: ExtensionRefreshState

    var body: some View {
        switch state {
        case .active:
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.secondary)
                .help("Refreshes in the background")
        case .idle:
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .foregroundStyle(.tertiary)
                .help("Background refresh is off — enable it from Actions")
        case .failed(let message):
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .help(firstLine(message))
        }
    }

    /// Failures arrive with a JS stack; the tooltip wants the headline.
    private func firstLine(_ message: String) -> String {
        String(message.split(separator: "\n").first ?? "Background refresh failed.")
    }
}
