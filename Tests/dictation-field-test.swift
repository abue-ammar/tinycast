import AppKit
import SwiftUI

@main
@MainActor
struct DictationFieldTest {
    static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        try await testDelivery()
        try await testScopedCancellation()
        try await testChatSwitch()
        try await testWindowClose()
        try await testQueuedCancellation(closing: false)
        try await testQueuedCancellation(closing: true)
        print("ALL PASSED")
    }

    private static func testDelivery() async throws {
        for mode in [DictationMode.toggle, .pushToTalk] {
            let fixture = Fixture()
            fixture.settings.dictationMode = mode
            let editor = ComposerTextView()
            try await fixture.start(into: editor)
            fixture.coordinator.toggle(into: editor)
            try await wait { fixture.models.pending != nil }
            fixture.models.finish("Spoken words")
            try await wait { fixture.coordinator.field == nil }
            expect(editor.string == "Spoken words", "Both shortcut modes insert the field's transcript")
            expect(Paster.copies.isEmpty, "A field mic ignores the copy-only destination setting")
        }
    }

    private static func testScopedCancellation() async throws {
        let fixture = Fixture()
        let editor = ComposerTextView()
        fixture.coordinator.toggle(into: editor)
        fixture.coordinator.cancel(in: editor)
        try await wait { fixture.capture.stopCount > 0 }
        expect(fixture.coordinator.field == nil, "Cancellation covers a recording still starting")
        expect(!fixture.capture.isRecording, "A canceled start cannot leave recording active")

        try await fixture.start(into: editor)
        fixture.coordinator.cancel(in: ComposerTextView())
        expect(fixture.capture.isRecording, "Another editor cannot cancel this session")
        expect(fixture.coordinator.field != nil, "Unrelated teardown preserves the field owner")
        fixture.coordinator.cancel(in: editor)
        try await wait { !fixture.capture.isRecording }
    }

    private static func testChatSwitch() async throws {
        let fixture = Fixture()
        let state = SurfaceState()
        let first = state.chat
        let second = Draft("Second draft")
        let surface = Surface(state: state, dictation: fixture.coordinator)
        defer { surface.close() }
        try await wait { surface.editor != nil }
        let editor = surface.editor!
        try await fixture.start(into: editor)
        fixture.coordinator.accept()
        try await wait { fixture.models.pending != nil }
        state.chat = second
        try await wait { surface.editor?.string == second.text }
        expect(surface.editor === editor, "Chat switching exercises the same reused editor")
        expect(fixture.coordinator.field == nil, "Rebinding cancels the old chat's transcription")
        fixture.models.finish("Late speech for the first chat")
        try await wait { fixture.models.finished }
        await fixture.queue.drain()
        expect(first.text == "First draft", "Canceled transcription leaves the original draft intact")
        expect(second.text == "Second draft", "Canceled transcription cannot enter the new chat")
        expect(fixture.messages.isEmpty, "Destination cancellation does not report an insertion error")
    }

    private static func testWindowClose() async throws {
        let fixture = Fixture()
        let state = SurfaceState()
        let surface = Surface(state: state, dictation: fixture.coordinator)
        try await wait { surface.editor != nil }
        let oldEditor = surface.editor!
        try await fixture.start(into: oldEditor)
        surface.close()
        try await wait { fixture.coordinator.field == nil && !fixture.capture.isRecording }
        expect(!oldEditor.isEditable, "Teardown rejects delayed in-process writes")
        expect(oldEditor.delegate == nil, "Teardown releases the old draft binding")
        expect(oldEditor.onDropFiles == nil, "Teardown releases attachment callbacks")

        let reopened = Surface(state: state, dictation: fixture.coordinator)
        defer { reopened.close() }
        try await wait { reopened.editor != nil }
        expect(reopened.editor !== oldEditor, "Reopening creates a fresh editor")
        try await fixture.start(into: reopened.editor!)
        expect(fixture.capture.isRecording, "The reopened field can start its own recording")
        fixture.coordinator.cancel(in: reopened.editor!)
        try await wait { !fixture.capture.isRecording }
    }

    private static func testQueuedCancellation(closing: Bool) async throws {
        let fixture = Fixture()
        let state = SurfaceState()
        let first = state.chat
        let surface = Surface(state: state, dictation: fixture.coordinator)
        defer { surface.close() }
        try await wait { surface.editor != nil }
        let editor = surface.editor!
        var release: CheckedContinuation<Void, Never>?
        fixture.queue.enqueue(isAutomatic: false) {
            await withCheckedContinuation { release = $0 }
        }
        try await wait { release != nil }
        try await fixture.start(into: editor)
        fixture.coordinator.accept()
        try await wait { fixture.models.pending != nil }
        fixture.models.finish("Already transcribed")
        try await wait { !fixture.panel.isVisible }
        expect(fixture.coordinator.field?.isTranscribing == true, "Queued insertion retains its session")

        if closing {
            surface.close()
        } else {
            state.chat = Draft("New chat")
            try await wait { surface.editor?.string == "New chat" }
        }
        try await wait { fixture.coordinator.field == nil }
        release?.resume()
        await fixture.queue.drain()
        expect(first.text == "First draft", "Queued speech cannot write into its canceled draft")
        expect(state.chat.text == (closing ? "First draft" : "New chat"), "Queued speech cannot cross chats")
        expect(fixture.messages.isEmpty, "Discarding queued speech is silent")
    }

    private static func wait(until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw CocoaError(.coderInvalidValue) }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        print("PASS  \(message)")
    }

    @MainActor
    private final class Fixture {
        let settings = AppSettings()
        let models = DictationModelStore()
        let queue = DeliveryQueue()
        var messages: [String] = []
        lazy var coordinator = DictationCoordinator(
            settings: settings, hotKeys: HotKeyManager(), models: models,
            injector: TextInjector(
                clipboardManager: ClipboardManager(), settings: settings, deliveryQueue: queue),
            audioDucker: DictationAudioDucker(), confirmEnable: { false },
            showMessage: { [weak self] message, _ in self?.messages.append(message) })

        var capture: DictationCapture { DictationCapture.latest! }
        var panel: DictationPanelController { DictationPanelController.latest! }

        func start(into editor: ComposerTextView) async throws {
            coordinator.toggle(into: editor)
            try await wait { capture.isRecording }
            expect(coordinator.field?.editor == ObjectIdentifier(editor), "The session belongs to its editor")
        }
    }

    @MainActor
    @Observable
    fileprivate final class Draft {
        let id = UUID()
        var text: String
        init(_ text: String) { self.text = text }
    }

    @MainActor
    @Observable
    fileprivate final class SurfaceState {
        var chat = Draft("First draft")
    }

    private struct Root: View {
        let state: SurfaceState
        let dictation: DictationCoordinator

        var body: some View { Composer(chat: state.chat, dictation: dictation) }
    }

    private struct Composer: View {
        let chat: Draft
        let dictation: DictationCoordinator
        @State private var handle = ComposerTextViewHandle()
        @State private var targeted = false

        var body: some View {
            @Bindable var chat = chat
            ChatComposerTextView(
                text: $chat.text, focusKey: chat.id, maximumTextHeight: 180, handle: handle,
                isFileDragTargeted: $targeted, onDropFiles: { _ in },
                onInvalidate: { dictation.cancel(in: $0) }, onSubmit: {})
        }
    }

    @MainActor
    private final class Surface {
        private var window: NSWindow?

        init(state: SurfaceState, dictation: DictationCoordinator) {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 200),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: Root(state: state, dictation: dictation))
            window.contentView?.layoutSubtreeIfNeeded()
            self.window = window
        }

        var editor: ComposerTextView? { window?.contentView.flatMap(Self.findEditor) }

        func close() {
            window?.close()
            window = nil
        }

        private static func findEditor(_ view: NSView) -> ComposerTextView? {
            if let editor = view as? ComposerTextView { return editor }
            return view.subviews.lazy.compactMap(findEditor).first
        }
    }
}

@MainActor
final class AppSettings {
    var snippetsEnabled = false
    var dictationEnabled = true
    var dictationMode = DictationMode.toggle
    var dictationModel = DictationModel.redux
    var dictationMicrophone: String?
    var dictationLanguage: String?
    var dictationDestination = DictationDestination.copy
    var dictationAdaptsCapitalization = true
}

enum HotKeyAction { case dictation }

@MainActor
final class HotKeyManager {
    struct Binding {
        var shortcut: Int?
        var holdKey: Int?
    }
    func binding(for action: HotKeyAction) -> Binding? { nil }
    func conflictOwner(of binding: Binding, excluding action: HotKeyAction) -> String? { nil }
}

@MainActor
final class DictationCapture {
    static weak var latest: DictationCapture?
    var onLevels: (([Float]) -> Void)?
    var onLimit: (() -> Void)?
    var isRecording = false
    var stopCount = 0

    init() { Self.latest = self }
    func start(microphoneID: String?) async throws { isRecording = true }
    func stop() async -> [Float] {
        isRecording = false
        stopCount += 1
        return [Float](repeating: 0, count: 1_600)
    }
}

@MainActor
final class DictationModelStore {
    var pending: CheckedContinuation<String, any Error>?
    var finished = false

    func isInstalled(_ model: DictationModel) -> Bool { true }
    func download(_ model: DictationModel) async throws {}
    func delete(_ model: DictationModel) async throws {}
    func stop() async {}
    func prepareForTermination() {}

    func transcribe(_ samples: [Float], model: DictationModel, language: String?) async throws -> String {
        defer { finished = true }
        return try await withCheckedThrowingContinuation { pending = $0 }
    }

    func finish(_ text: String) {
        let continuation = pending
        pending = nil
        continuation?.resume(returning: text)
    }
}

@MainActor
final class DictationPanelController {
    enum Phase { case listening, transcribing }
    @MainActor
    final class State {
        var phase = Phase.listening
        var levels: [Float] = []
    }
    static weak var latest: DictationPanelController?
    let state = State()
    var onAccept: (() -> Void)?
    var onCancel: (() -> Void)?
    var isVisible = false
    init() { Self.latest = self }
    func show() { isVisible = true }
    func close() { isVisible = false }
}

@MainActor
final class DictationAudioDucker {
    func begin() {}
    func end() {}
    func restoreImmediately() {}
}

@MainActor
final class ClipboardManager {
    static let internalType = NSPasteboard.PasteboardType("com.tinycast.internal")
    func prepareForTinycastPasteboardMutation() {}
    func synchronizeAfterTinycastPasteboardMutation(changeCount: Int) {}
}

enum Permissions {
    @discardableResult
    static func ensureAccessibility() -> Bool { false }
    static func isAccessibilityTrusted() -> Bool { false }
}

@MainActor
enum Paster {
    static let tinycastEventTag: Int64 = 0x54494E59
    static var copies: [String] = []
    static func copyPlainText(_ text: String) { copies.append(text) }
    static func postCommandV(toPid pid: pid_t? = nil) {}
    static func postCommandC(toPid pid: pid_t? = nil) {}
}

enum DialogTone { case danger }
