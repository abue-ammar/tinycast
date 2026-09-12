import AVKit
import SwiftUI
import UniformTypeIdentifiers

/// QuickLook draws a movie's first frame but never plays one inside a non-activating panel.
struct FileSearchMediaPlayer: View {

    @Environment(PaletteState.self) private var palette
    let url: URL
    @State private var player: AVPlayer?

    static func plays(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .movie) || type.conforms(to: .audio)
    }

    /// One key for both teardown triggers, so no `onChange` races the task.
    private struct PlaybackKey: Equatable {
        let url: URL
        let isVisible: Bool
    }

    var body: some View {
        PlayerSurface(player: player)
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

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause()
        view.player = nil
    }
}
