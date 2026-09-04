import SwiftUI

/// Seats a picker's list below its control, or above it when the bottom would cut it off.
/// The rule is `ExtensionFormMetrics.placement`, which a harness drives directly; this only
/// measures the control against the form and applies what the rule decides.
struct ExtensionPopoverPlacement: ViewModifier {
    let rowCount: Int
    let hasSearchField: Bool
    /// Reported back so the control can point its chevron the way the list actually opened.
    let onFlip: (Bool) -> Void

    @State private var anchor: CGRect = .zero
    @State private var containerHeight: CGFloat = 0

    private var height: CGFloat {
        ExtensionFormMetrics.popoverHeight(rows: rowCount, hasSearchField: hasSearchField)
    }

    private var placement: ExtensionFormMetrics.Placement {
        ExtensionFormMetrics.placement(
            anchor: anchor, popoverHeight: height, containerHeight: containerHeight)
    }

    func body(content: Content) -> some View {
        content
            // The rule works in the form's space; the offset is from the control's own top edge.
            .offset(y: placement.y - anchor.minY)
            .background {
                // Measured on the layer behind the list, so measuring cannot move what it measures.
                Color.clear
                    .onGeometryChange(for: Anchor.self) { proxy in
                        Anchor(
                            frame: proxy.frame(in: .named(ExtensionFormCoordinateSpace.name)),
                            container: proxy.bounds(of: .named(ExtensionFormCoordinateSpace.name))?
                                .height ?? 0)
                    } action: { measured in
                        anchor = measured.frame
                        containerHeight = measured.container
                    }
            }
            .onChange(of: placement.flipped) { onFlip(placement.flipped) }
            .onAppear { onFlip(placement.flipped) }
    }

    private struct Anchor: Equatable {
        var frame: CGRect = .zero
        var container: CGFloat = 0
    }
}

/// The space a picker's list is placed in: the scrolling form itself.
enum ExtensionFormCoordinateSpace {
    static let name = "extension-form"
}

extension View {
    /// Opens a list downward, or upward when the form's bottom edge would cut it off.
    func extensionPopoverPlacement(
        rowCount: Int, hasSearchField: Bool, onFlip: @escaping (Bool) -> Void
    ) -> some View {
        modifier(
            ExtensionPopoverPlacement(
                rowCount: rowCount, hasSearchField: hasSearchField, onFlip: onFlip))
    }
}
