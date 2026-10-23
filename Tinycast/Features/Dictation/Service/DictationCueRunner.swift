import AppKit

@MainActor
final class DictationCueRunner {
    enum Cue { case start, stop }

    private static let resources = URL(
        filePath: "/System/Library/PrivateFrameworks/AssistantServices.framework/Resources",
        directoryHint: .isDirectory)

    private let startSound = NSSound(
        contentsOf: resources.appending(path: "dt-begin.caf"), byReference: true)
    private let stopSound = NSSound(
        contentsOf: resources.appending(path: "dt-confirm.caf"), byReference: true)

    func play(_ cue: Cue) {
        startSound?.stop()
        stopSound?.stop()
        (cue == .start ? startSound : stopSound)?.play()
    }
}
