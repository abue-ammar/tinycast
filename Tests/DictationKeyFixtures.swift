import Foundation
import Observation

@MainActor
@Observable
final class HotKeyManager {
    var recordingAction: Int?
    var bindsDictationKey = true
}
