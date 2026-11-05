import SwiftUI

/// Alone in reading `stage`, so a download tick never re-renders the palette around it.
struct UpdatePill: View {
    private enum Glyph {
        case symbol(String)
        case spinner
        case ring(Double)
    }

    private struct Content {
        let tint: Color
        let glyph: Glyph
        let title: String
        var detail: String?
        var action: (title: String, perform: () -> Void)?
        let closeTitle: String
    }

    private static let tintOpacity = 0.16
    private static let actionOpacity = 0.22
    private static let glyphSize: CGFloat = 16
    private static let closeGlyphSize: CGFloat = 10
    private static let ringStroke: CGFloat = 2

    @Environment(UpdateCoordinator.self) private var updates
    @Environment(\.metrics) private var metrics

    var body: some View {
        let content = content
        ZStack {
            if let content {
                pill(content)
                    .transition(.scale(scale: 0.5, anchor: .leading).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.2), value: content?.title)
    }

    private var content: Content? {
        switch updates.stage {
        case .idle, .checking:
            return nil
        case .available(let release):
            return Content(
                tint: Theme.Colors.progress, glyph: .symbol("arrow.down.circle"),
                title: "v\(release.version.description)",
                action: (String(localized: "Update"), updates.install),
                closeTitle: String(localized: "Later"))
        case .installing(_, let phase):
            return Content(
                tint: Theme.Colors.progress, glyph: phase.fraction.map(Glyph.ring) ?? .spinner,
                title: phase.message,
                detail: phase.fraction?.formatted(.percent.precision(.fractionLength(0))),
                closeTitle: String(localized: "Cancel"))
        case .readyToRelaunch:
            return Content(
                tint: Theme.Colors.success, glyph: .symbol("checkmark.circle.fill"),
                title: String(localized: "Update ready"),
                action: (String(localized: "Relaunch"), updates.relaunch),
                closeTitle: String(localized: "Later"))
        case .failed:
            return Content(
                tint: Theme.Colors.destructive, glyph: .symbol("exclamationmark.circle.fill"),
                title: String(localized: "Update failed"),
                action: (String(localized: "Details"), updates.showFailure),
                closeTitle: String(localized: "Close"))
        }
    }

    private func pill(_ content: Content) -> some View {
        HStack(spacing: metrics.spacing.md) {
            glyph(content.glyph)
            Text(content.title)
            if let detail = content.detail {
                Text(detail).monospacedDigit()
            }
            if let action = content.action {
                BarButton(action: action.perform) { Text(action.title) }
                    .background(content.tint.opacity(Self.actionOpacity), in: Capsule())
            }
            closeButton(title: content.closeTitle)
        }
        .font(metrics.typography.bar)
        .foregroundStyle(content.tint)
        .lineLimit(1)
        .padding(.leading, metrics.spacing.lg)
        .padding(.trailing, metrics.spacing.xs)
        .frame(height: metrics.size.menuButton)
        .glassEffect(
            .regular.tint(content.tint.opacity(Self.tintOpacity)).interactive(), in: Capsule()
        )
        .fixedSize()
        .padding(.leading, metrics.spacing.md)
    }

    private func closeButton(title: String) -> some View {
        BarButton(isCompact: true, action: updates.dismiss) {
            SymbolImage(name: "xmark", size: metrics.scaled(Self.closeGlyphSize), monochrome: true)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(
                    width: metrics.scaled(Self.glyphSize), height: metrics.scaled(Self.glyphSize))
        }
        .background(Theme.Colors.controlSurface, in: Circle())
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private func glyph(_ glyph: Glyph) -> some View {
        let size = metrics.scaled(Self.glyphSize)
        switch glyph {
        case .symbol(let name):
            SymbolImage(name: name, size: size, monochrome: true)
        case .spinner:
            SymbolImage(name: "progress.indicator", size: size, monochrome: true)
                .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing)
        case .ring(let fraction):
            let stroke = metrics.scaled(Self.ringStroke)
            ZStack {
                Circle().stroke(lineWidth: stroke).opacity(0.25)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .padding(stroke / 2)
            .frame(width: size, height: size)
        }
    }
}
