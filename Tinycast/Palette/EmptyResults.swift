import SwiftUI

struct EmptyResults: View {
    let text: String

    @Environment(\.metrics) private var metrics

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(metrics.typography.placeholderGlyph)
                .symbolRenderingMode(.hierarchical).foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
