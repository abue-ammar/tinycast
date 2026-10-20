import AppKit

@MainActor
final class DictationCueRunner {
    private let sound = NSSound(named: "Pop")

    func play() {
        sound?.stop()
        sound?.play()
    }
}
