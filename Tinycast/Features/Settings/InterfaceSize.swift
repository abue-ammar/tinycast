import CoreGraphics

/// How large the palette and its floating siblings render; an unset key reads as `.standard`.
enum InterfaceSize: String, CaseIterable, Identifiable, Sendable {
    case standard
    case large
    case larger

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Default"
        case .large: "Large"
        case .larger: "Larger"
        }
    }

    var scale: CGFloat {
        switch self {
        case .standard: 1
        case .large: 1.1
        case .larger: 1.2
        }
    }

    var metrics: InterfaceMetrics { InterfaceMetrics(scale: scale) }
}
