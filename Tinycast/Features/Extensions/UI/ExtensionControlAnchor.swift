import SwiftUI

/// The space a picker's list is placed in: the scrolling form itself.
enum ExtensionFormCoordinateSpace {
    static let name = "extension-form"
}

/// Where a control sits inside the form, measured so its list can decide which way to open.
struct ExtensionControlAnchor: Equatable {
    var frame: CGRect = .zero
    var containerHeight: CGFloat = 0
}

/// Measures a control against the form; a list reading its own frame would feed back.
struct ExtensionAnchorReader: ViewModifier {
    let onMeasure: (ExtensionControlAnchor) -> Void

    func body(content: Content) -> some View {
        content.background {
            Color.clear.onGeometryChange(for: ExtensionControlAnchor.self) { proxy in
                ExtensionControlAnchor(
                    frame: proxy.frame(in: .named(ExtensionFormCoordinateSpace.name)),
                    containerHeight: proxy.bounds(of: .named(ExtensionFormCoordinateSpace.name))?
                        .height ?? 0)
            } action: { onMeasure($0) }
        }
    }
}

extension View {
    /// Publishes this control's place in the form, for the list it opens.
    func extensionControlAnchor(
        _ onMeasure: @escaping (ExtensionControlAnchor) -> Void
    ) -> some View {
        modifier(ExtensionAnchorReader(onMeasure: onMeasure))
    }
}
