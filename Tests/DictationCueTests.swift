import Foundation

@main
@MainActor
struct DictationCueTests {
    static func main() {
        let names = ["dt-begin.caf", "dt-confirm.caf"]
        let resources = "/System/Library/PrivateFrameworks/AssistantServices.framework/Resources/"
        for missing in [Set<String>(), Set([names[0]]), Set([names[1]]), Set(names)] {
            NSSound.missing = missing
            NSSound.paths = []
            let runner = DictationCueRunner()
            precondition(NSSound.paths == names.map { resources + $0 }, "Use macOS dictation resources")
            for (cue, name) in [(DictationCueRunner.Cue.start, names[0]), (.stop, names[1])] {
                NSSound.events = []
                runner.play(cue)
                let stops = names.filter { !missing.contains($0) }.map { "stop \($0)" }
                let plays = missing.contains(name) ? [] : ["play \(name)"]
                precondition(NSSound.events == stops + plays, "Stop previous cues before playing")
            }
        }
        print("ALL PASSED")
    }
}

@MainActor
final class NSSound {
    static var missing: Set<String> = []
    static var paths: [String] = []
    static var events: [String] = []
    private let name: String

    init?(contentsOf url: URL, byReference: Bool) {
        precondition(byReference, "System sounds are loaded by reference")
        Self.paths.append(url.path)
        name = url.lastPathComponent
        if Self.missing.contains(name) { return nil }
    }

    func stop() { Self.events.append("stop \(name)") }
    func play() { Self.events.append("play \(name)") }
}
