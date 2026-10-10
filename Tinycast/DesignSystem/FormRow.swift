import SwiftUI

struct FormRow<Content: View>: View {
    let title: String
    let alignment: VerticalAlignment
    let labelInset: CGFloat?
    let content: Content

    @Environment(\.metrics) private var metrics

    init(
        _ title: String, alignment: VerticalAlignment = .center, labelInset: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.alignment = alignment
        self.labelInset = labelInset
        self.content = content()
    }

    var body: some View {
        let labelWidth = (metrics.size.panelWidth * 0.16).rounded()
        HStack(alignment: alignment, spacing: metrics.spacing.xxl) {
            Text(title)
                .font(metrics.typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: labelWidth, alignment: .trailing)
                .padding(.top, labelInset ?? (alignment == .top ? metrics.spacing.lg : 0))
            content.frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: labelWidth, height: 0)
        }
    }
}
