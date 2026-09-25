// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import AppKit
import SwiftUI

/// One display's share of the preview: the desk blurred and dimmed, the room's cards on top.
struct RoomPreviewView: View {
    let model: RoomPreviewModel
    /// This display's top-left in AX space. AX and SwiftUI both grow down, so no flip is needed.
    let origin: CGPoint
    let size: CGSize

    private var bounds: CGRect { CGRect(origin: origin, size: size) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.Colors.roomPreviewDim
            ForEach(model.cards.filter { $0.frame.intersects(bounds) }) { card in
                RoomPreviewCardView(
                    card: card,
                    avoiding: model.avoiding.map { $0.offsetBy(dx: -card.frame.minX, dy: -card.frame.minY) }
                )
                .frame(width: card.frame.width, height: card.frame.height)
                .offset(x: card.frame.minX - origin.x, y: card.frame.minY - origin.y)
                .transition(
                    .asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: Theme.Duration.roomCardEnter)),
                        removal: .opacity.animation(.easeIn(duration: Theme.Duration.roomCardExit))))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(DeskBlur())
        .accessibilityHidden(true)
    }
}

/// A window-to-be: a title bar naming the app and window, the app's icon in its body.
private struct RoomPreviewCardView: View {
    let card: RoomPreviewCard
    /// The palette's frame in this card's coordinates, which the icon stays out from under.
    let avoiding: CGRect?

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.roomCard, style: .continuous)
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            Color.clear
        }
        .overlay(alignment: .top) { icon }
        .background(shape.fill(Theme.Colors.roomCardFill))
        .overlay(shape.strokeBorder(Theme.Colors.roomCardStroke, lineWidth: Theme.Size.roomCardStroke))
        .clipShape(shape)
        .shadow(
            color: Theme.Colors.roomCardShadow, radius: Theme.Size.roomCardShadowRadius,
            y: Theme.Size.roomCardShadowOffset)
    }

    private var titleBar: some View {
        HStack(spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.md) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(Theme.Colors.roomCardDot)
                        .frame(width: Theme.Size.roomCardDot, height: Theme.Size.roomCardDot)
                }
            }
            Text(card.appName)
                .font(.headline)
                .foregroundStyle(.primary)
                .layoutPriority(1)
            if !card.title.isEmpty {
                Text("—  \(card.title)")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(height: Theme.Size.roomCardTitleBar)
    }

    @ViewBuilder
    private var icon: some View {
        let body = CGSize(width: card.frame.width, height: card.frame.height - Theme.Size.roomCardTitleBar)
        if let appURL = card.appURL, card.frame.height >= Theme.Size.roomCardIconMinHeight {
            let side = iconSide
            EntryIconView(source: .file(stamp: FileIconStamp.value(for: appURL)), fileURL: appURL)
                .frame(width: side, height: side)
                .offset(y: Theme.Size.roomCardTitleBar + iconCenter(in: body, side: side) - side / 2)
        }
    }

    private var iconSide: CGFloat {
        let large = Theme.Size.roomCardLargeIconMinSide
        return card.frame.width > large && card.frame.height > large
            ? Theme.Size.roomCardIconLarge : Theme.Size.roomCardIcon
    }

    /// The body's middle, or the middle of its larger part the palette leaves uncovered.
    private func iconCenter(in body: CGSize, side: CGFloat) -> CGFloat {
        let top = Theme.Size.roomCardTitleBar
        guard let avoiding,
            avoiding.maxY > top, avoiding.minY < top + body.height,
            avoiding.maxX > (body.width - side) / 2, avoiding.minX < (body.width + side) / 2
        else { return body.height / 2 }
        let above = max(0, avoiding.minY - top)
        let below = max(0, top + body.height - avoiding.maxY)
        return above >= below ? above / 2 : body.height - below / 2
    }
}

/// Behind-window blur for the whole display, the way Mission Control softens the desk.
private struct DeskBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .fullScreenUI
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
