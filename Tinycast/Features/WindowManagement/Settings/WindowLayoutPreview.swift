import AppKit
import SwiftUI

/// The editor's left column: one display drawn to scale, its entries over it, and the tabs.
struct WindowLayoutPreview: View {
    let draft: WindowLayoutDraft
    /// Resolved once by the sheet: an AX read per render would cost a round trip per keystroke.
    let screens: [WindowLayoutScreen]
    let gap: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            WindowLayoutPreviewCanvas(draft: draft, screen: selectedScreen, gap: gap)
                .frame(
                    width: Theme.Size.layoutPreview.width,
                    height: Theme.Size.layoutPreview.height
                )

            // Beside the caption, not over the canvas: a tab must never cover a window rect.
            HStack(spacing: Theme.Spacing.md) {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                WindowLayoutDisplayTabs(draft: draft, displays: tabs)
            }
            .frame(width: Theme.Size.layoutPreview.width)
        }
    }

    private var tabs: [WindowLayoutDisplay] {
        draft.tabs(connected: screens.map(\.display))
    }

    /// The geometry for the selected tab, or nil when that display is not connected.
    private var selectedScreen: WindowLayoutScreen? {
        guard let uuid = draft.selectedDisplayUUID else { return nil }
        return screens.first { $0.display.uuid == uuid }
    }

    private var caption: String {
        guard let uuid = draft.selectedDisplayUUID,
            let display = tabs.first(where: { $0.uuid == uuid })
        else { return "No display selected" }
        guard let screen = selectedScreen else { return "\(display.name) · not connected" }
        // Points, not pixels: nothing in this feature touches `backingScaleFactor`.
        let size = screen.screen.frame.size
        return "\(display.name) · \(Int(size.width)) × \(Int(size.height))"
    }
}

/// One display to scale with a rounded rect per entry on it. Draws; decides nothing.
struct WindowLayoutPreviewCanvas: View {
    let draft: WindowLayoutDraft
    let screen: WindowLayoutScreen?
    let gap: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let screen {
                    // The plate is the display itself, at its own aspect ratio.
                    let ground = ground(in: proxy.size, display: screen.screen.visibleFrame)
                    plate
                        .frame(width: ground.width, height: ground.height)
                        .position(x: ground.midX, y: ground.midY)
                    ForEach(placements(on: screen), id: \.entry.id) { placed in
                        entryRect(placed, ground: ground, display: screen.screen.visibleFrame)
                    }
                } else {
                    plate
                    Text("This display isn't connected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var plate: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .fill(Theme.Colors.layoutPreviewGround)
    }

    private struct Placed {
        let entry: WindowLayoutEntry
        let frame: CGRect
    }

    /// Every rect comes from the resolver the runner uses; nothing here re-derives geometry.
    private func placements(on screen: WindowLayoutScreen) -> [Placed] {
        draft.entries(onDisplay: screen.display.uuid).compactMap { entry in
            WindowLayoutGeometry.resolve(entry, on: screen.screen, gap: gap)
                .map { Placed(entry: entry, frame: $0) }
        }
    }

    /// Fit, not fill: a 16:10 display stretched into a 16:9 box misdraws every rect inside it.
    private func ground(in box: CGSize, display: CGRect) -> CGRect {
        guard display.width > 0, display.height > 0 else { return .zero }
        let scale = min(box.width / display.width, box.height / display.height)
        let size = CGSize(width: display.width * scale, height: display.height * scale)
        return CGRect(
            x: (box.width - size.width) / 2, y: (box.height - size.height) / 2,
            width: size.width, height: size.height)
    }

    @ViewBuilder
    private func entryRect(_ placed: Placed, ground: CGRect, display: CGRect) -> some View {
        let isSelected = placed.entry.id == draft.selectedEntryID
        let scale = display.width > 0 ? ground.width / display.width : 0
        let rect = CGRect(
            x: ground.minX + (placed.frame.minX - display.minX) * scale,
            y: ground.minY + (placed.frame.minY - display.minY) * scale,
            width: placed.frame.width * scale, height: placed.frame.height * scale)
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous)

        shape
            .fill(
                isSelected
                    ? Theme.Colors.layoutPreviewWindowSelected : Theme.Colors.layoutPreviewWindow
            )
            .overlay(shape.stroke(isSelected ? Color.accentColor : Theme.Colors.border))
            .overlay(icon(for: placed.entry.bundleID))
            .frame(width: max(1, rect.width), height: max(1, rect.height))
            .position(x: rect.midX, y: rect.midY)
            // Drawn last, since a layout may legitimately stack two windows.
            .zIndex(isSelected ? 1 : 0)
    }

    @ViewBuilder
    private func icon(for bundleID: String) -> some View {
        if let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map({ NSWorkspace.shared.icon(forFile: $0.path) })
        {
            Image(nsImage: icon)
                .resizable()
                .frame(width: Theme.Size.layoutPreviewIcon, height: Theme.Size.layoutPreviewIcon)
        }
    }

    private var accessibilityDescription: String {
        guard let screen else { return "Preview, display not connected" }
        let count = draft.entries(onDisplay: screen.display.uuid).count
        let windows = count == 1 ? "1 window" : "\(count) windows"
        return "Preview of \(screen.display.name), \(windows)"
    }
}
