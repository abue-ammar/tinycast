import AppKit
import SwiftUI

/// The system segmented control at one size for life, each segment as wide as its label.
///
/// Left to size itself, the control opens tight around its labels and widens the first time the
/// selection changes, under the pointer; stating each segment's width opens it already settled.
struct SteadySegmentedPicker<Value: Hashable>: NSViewRepresentable {
    struct Option {
        let value: Value
        let title: String
    }

    let title: String
    let options: [Option]
    @Binding var selection: Value

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: options.map(\.title), trackingMode: .selectOne,
            target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        control.setAccessibilityLabel(title)
        let font = control.font ?? .systemFont(ofSize: NSFont.systemFontSize)
        for (index, option) in options.enumerated() {
            let label = (option.title as NSString).size(withAttributes: [.font: font]).width
            control.setWidth(
                (label + Theme.Size.segmentLabelInset * 2).rounded(.up), forSegment: index)
        }
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        control.selectedSegment = options.firstIndex { $0.value == selection } ?? -1
    }

    /// The control's own idea of its width also shrinks after the first switch, so it is not asked.
    func sizeThatFits(
        _ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context
    ) -> CGSize? {
        let width = (0..<nsView.segmentCount).reduce(0) { $0 + nsView.width(forSegment: $1) }
        return CGSize(width: width, height: nsView.intrinsicContentSize.height)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: SteadySegmentedPicker

        init(_ parent: SteadySegmentedPicker) {
            self.parent = parent
        }

        @objc func changed(_ sender: NSSegmentedControl) {
            guard parent.options.indices.contains(sender.selectedSegment) else { return }
            parent.selection = parent.options[sender.selectedSegment].value
        }
    }
}
