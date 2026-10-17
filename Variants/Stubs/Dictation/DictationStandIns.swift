import SwiftUI

@MainActor
final class DictationAudioDucker {
    func recover() {}
    func restoreImmediately() {}
    func waitForTransition() async {}
}

@MainActor
@Observable
final class DictationModelStore {
    init(idleRelease: DictationIdleRelease) {}
    func isInstalled(_ model: DictationModel) -> Bool { false }
    func setIdleRelease(_ option: DictationIdleRelease) {}
    func stop() async {}
}

struct DictationField: Equatable {
    let editor: ObjectIdentifier
    var isTranscribing = false
}

@MainActor
@Observable
final class DictationCoordinator {
    let models: DictationModelStore
    private let showMessage: (String, DialogTone) -> Void
    private(set) var field: DictationField?

    init(
        settings: AppSettings, hotKeys: HotKeyManager, models: DictationModelStore,
        injector: TextInjector, audioDucker: DictationAudioDucker,
        confirmEnable: @escaping () async -> Bool,
        showMessage: @escaping (String, DialogTone) -> Void
    ) {
        self.models = models
        self.showMessage = showMessage
    }

    /// Ignores `dictationEnabled`, so AI Chat never shows a mic button.
    var isEnabled: Bool { false }
    var hasModel: Bool { false }

    func pressed() { showMessage(ExcludedFeature.message("Dictation"), .danger) }
    func released() {}
    func cancel() {}
    func cancel(in editor: any InjectableTextView) {}
    func toggle(into editor: any InjectableTextView) { pressed() }
    func prepareForTermination() {}
}

struct DictationSettingsView: View {
    var body: some View {
        ExcludedFeaturePane(feature: "Dictation", symbol: "waveform")
    }
}
