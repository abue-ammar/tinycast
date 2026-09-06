import AVKit
import SwiftUI

/// The preview pane's stage for a referenced file: a poster frame, or a player for media.
struct FilePreviewStage: View {
    let path: String

    /// One stat, off the render path: `body` re-runs per keystroke and must not touch the disk.
    struct Probe: Equatable, Sendable {
        var exists = false
        var isDirectory = false
    }

    @State private var probe: Probe?

    private var url: URL { URL(fileURLWithPath: path) }

    var body: some View {
        stage.task(id: path) { probe = await Self.probe(path) }
    }

    @ViewBuilder private var stage: some View {
        let kind = ClipboardFileKind.of(path: path, isDirectory: probe?.isDirectory ?? false)
        switch probe {
        case .some(let probe) where !probe.exists: MissingFileStage()
        case .some where kind.isPlayable: MediaPreviewPlayer(url: url, isAudio: kind == .audio)
        default:
            FileThumbnailStage(
                url: url, maxPixel: Theme.Size.clipboardPreviewPixel, glyph: kind.systemImage)
        }
    }

    nonisolated private static func probe(_ path: String) async -> Probe {
        await Task.detached {
            let url = URL(fileURLWithPath: path)
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            return Probe(
                exists: FileManager.default.fileExists(atPath: path),
                isDirectory: values?.isDirectory == true)
        }.value
    }
}

/// The recorded path is still the answer to "where was it?", so the row keeps it and says this.
private struct MissingFileStage: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "doc.badge.exclamationmark")
                .font(.system(.largeTitle))
                .symbolRenderingMode(.hierarchical)
            Text("File is no longer available")
                .font(Theme.Typography.rowTrailing)
        }
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
    }
}

/// A still, framed exactly as the image preview is, so every preview kind is one shape.
private struct FileThumbnailStage: View {
    let url: URL
    let maxPixel: CGFloat
    let glyph: String

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                    )
            } else {
                Image(systemName: glyph)
                    .font(.system(.largeTitle))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tertiary)
            }
        }
        .task(id: url) {
            if let hit = FilePreviewThumbnail.cached(url, maxPixel: maxPixel) {
                image = hit
                return
            }
            image = nil
            image = await FilePreviewThumbnail.loadAsync(url, maxPixel: maxPixel)
        }
    }
}

/// Owns the `AVPlayer`. Never autoplays: arrow-keying a list must not start twenty decodes.
private struct MediaPreviewPlayer: View {
    let url: URL
    let isAudio: Bool

    @Environment(PaletteState.self) private var palette
    @State private var player: AVPlayer?

    /// One key for both teardown triggers, so no `onChange` races the task.
    private struct PlaybackKey: Equatable {
        let url: URL
        let isVisible: Bool
    }

    var body: some View {
        PlayerSurface(player: player)
            .background { if isAudio { AudioPoster(url: url) } }
            .frame(height: Theme.Size.clipboardMediaHeight)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .task(id: PlaybackKey(url: url, isVisible: palette.isVisible)) {
                stop()
                guard palette.isVisible else { return }
                player = AVPlayer(url: url)
            }
            .onDisappear(perform: stop)
    }

    /// Dropping the item too: a paused player still holds its asset reader and decoder open.
    private func stop() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }
}

/// `AVPlayerView`, since SwiftUI's `VideoPlayer` traps instantiating its own generic metadata.
private struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer?

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = false
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        guard view.player !== player else { return }
        view.player = player
    }

    /// AppKit keeps decoding until the player is cleared, and dismantling is the last chance.
    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause()
        view.player = nil
    }
}

/// An audio asset draws nothing of its own, so its artwork sits behind the transport.
private struct AudioPoster: View {
    let url: URL

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "waveform")
                    .font(.system(.largeTitle))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tertiary)
            }
        }
        .task(id: url) {
            image = await FilePreviewThumbnail.loadAsync(url, maxPixel: 300)
        }
    }
}
