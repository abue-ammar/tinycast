import SwiftUI

struct EmptyResults: View {
    let text: String
    var detail: String?
    var systemImage = "magnifyingglass"

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage).font(.largeTitle)
                .symbolRenderingMode(.hierarchical).foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary)
            if let detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
