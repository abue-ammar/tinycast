import SwiftUI

extension SnippetTag.Color {
    var tint: SwiftUI.Color { SwiftUI.Color(nsColor: NSWorkspace.shared.fileLabelColors[labelIndex]) }

    private var labelIndex: Int {
        switch self {
        case .gray: 1
        case .green: 2
        case .purple: 3
        case .blue: 4
        case .yellow: 5
        case .red: 6
        case .orange: 7
        }
    }
}
