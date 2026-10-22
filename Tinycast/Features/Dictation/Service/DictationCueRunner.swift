import AppKit

@MainActor
final class DictationCueRunner {
    enum Cue { case start, stop }

    private let startSound = NSSound(named: "DictationStart")
    private let stopSound = NSSound(named: "DictationStop")

    func play(_ cue: Cue) {
        startSound?.stop()
        stopSound?.stop()
        (cue == .start ? startSound : stopSound)?.play()
    }
}
