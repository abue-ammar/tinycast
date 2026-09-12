import SwiftUI

/// Section label above a group of rows, shared by every palette list.
struct SectionHeader: View {
    @Environment(\.metrics) private var metrics
    let title: String
    /// The first header hugs the top; later ones get spacing above, reading as below.
    var isFirst = false
    /// A gear beside the label, for a section whose membership the reader chooses.
    var configure: (() -> Void)?
    var configureHelp = "Configure…"

    var body: some View {
        HStack(spacing: metrics.spacing.sm) {
            Text(title)
                .lineLimit(1)
            if let configure {
                Button(action: configure) {
                    Image(systemName: "gearshape")
                        .imageScale(.small)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(configureHelp)
            }
            Spacer(minLength: 0)
        }
        .font(metrics.typography.sectionHeader)
        .foregroundStyle(.secondary)
        .padding(.horizontal, metrics.spacing.md)
        .padding(.top, isFirst ? metrics.spacing.xs : metrics.spacing.sectionSpacing)
        .padding(.bottom, metrics.spacing.sectionHeaderBottom)
    }
}
