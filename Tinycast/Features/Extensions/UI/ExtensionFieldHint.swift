import SwiftUI

/// Carries a field's `info` text to the control, which a hover-only tooltip never reaches.
struct ExtensionFieldHint: ViewModifier {
    let info: String?

    func body(content: Content) -> some View {
        if let info, !info.isEmpty {
            content.accessibilityHint(Text(info))
        } else {
            content
        }
    }
}

extension View {
    /// The field's own explanation, spoken as well as shown.
    func extensionFieldHint(_ info: String?) -> some View {
        modifier(ExtensionFieldHint(info: info))
    }
}
