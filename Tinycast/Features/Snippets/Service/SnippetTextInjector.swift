import AppKit
import Carbon.HIToolbox

enum SnippetAccessibilityReplacement: Equatable {
    case delivered
    case unavailable
    case rejected

    /// Only `.unavailable` falls back to events; `.rejected` means the text moved, so fail closed.
    var fallsBackToEvents: Bool { self == .unavailable }
}

@MainActor
final class SnippetDeliveryCompletion {
    private let callback: @MainActor () -> Void
    private(set) var isConfirmed = false

    init(callback: @escaping @MainActor () -> Void = {}) {
        self.callback = callback
    }

    func confirm() {
        guard !isConfirmed else { return }
        isConfirmed = true
        callback()
    }
}

@MainActor
final class SnippetTextInjector {
    typealias AutomaticGeneration = UInt

    /// Generous for a responsive app, short enough that a wedged one can't stall a keystroke.
    private static let accessibilityTimeout: Float = 1

    private let clipboardManager: ClipboardManager
    private let settings: AppSettings
    private let deliveryQueue = SnippetDeliveryQueue()
    private var automaticGeneration: AutomaticGeneration = 0
    private var activePasteboardLease: TemporaryPasteboardLease?

    init(clipboardManager: ClipboardManager, settings: AppSettings) {
        self.clipboardManager = clipboardManager
        self.settings = settings
    }

    func prepareInteractiveExpansion(targetApp: NSRunningApplication?) -> Bool {
        guard targetApp?.isTerminated != true, Permissions.ensureAccessibility() else {
            activate(targetApp)
            return false
        }
        return true
    }

    func beginAutomaticExpansion(
        targetApp: NSRunningApplication?
    ) -> AutomaticGeneration? {
        cancelAutomaticExpansion()
        guard
            automaticExpansionIsAllowed(
                generation: automaticGeneration,
                targetApp: targetApp)
        else { return nil }
        return automaticGeneration
    }

    func cancelAutomaticExpansion(targetApp: NSRunningApplication? = nil) {
        automaticGeneration &+= 1
        deliveryQueue.cancelAutomatic()
        activate(targetApp)
    }

    func prepareForTermination() {
        automaticGeneration &+= 1
        deliveryQueue.cancelAll()
        finishPendingPasteboardOwnership()
    }

    func cancelArgumentPrompt(
        automaticGeneration: AutomaticGeneration?,
        targetApp: NSRunningApplication?
    ) {
        if automaticGeneration != nil {
            cancelAutomaticExpansion(targetApp: targetApp)
        } else {
            activate(targetApp)
        }
    }

    func automaticExpansionIsAllowed(
        generation: AutomaticGeneration,
        targetApp: NSRunningApplication?
    ) -> Bool {
        guard generation == automaticGeneration,
            settings.snippetsEnabled,
            Permissions.isAccessibilityTrusted(),
            !IsSecureEventInputEnabled(),
            let targetApp,
            !targetApp.isTerminated,
            targetApp.bundleIdentifier != Bundle.main.bundleIdentifier
        else { return false }
        return true
    }

    func captureExpansionContext(
        targetApp: NSRunningApplication?,
        clipboardHistory: [String]
    ) -> SnippetTemplateEngine.ExpansionContext {
        SnippetTemplateEngine.ExpansionContext(
            clipboardHistory: clipboardHistory,
            selection: selectedText(in: targetApp) ?? "",
            now: Date(),
            calendar: Calendar.current,
            locale: Locale.current,
            timeZone: .current)
    }

    func deliver(
        _ result: SnippetTemplateEngine.ExpansionResult,
        targetApp: NSRunningApplication?,
        expectedKeyword: String?,
        keywordLength: Int,
        automaticGeneration: AutomaticGeneration?,
        onDelivered: @escaping @MainActor () -> Void = {}
    ) {
        activate(targetApp)
        if let automaticGeneration {
            guard
                automaticExpansionIsAllowed(
                    generation: automaticGeneration,
                    targetApp: targetApp)
            else { return }
        } else {
            guard prepareInteractiveExpansion(targetApp: targetApp) else { return }
        }

        deliveryQueue.enqueue(isAutomatic: automaticGeneration != nil) { [weak self] in
            guard let self else { return }
            await self.performDelivery(
                result,
                targetApp: targetApp,
                expectedKeyword: expectedKeyword,
                keywordLength: keywordLength,
                automaticGeneration: automaticGeneration,
                onDelivered: onDelivered)
        }
    }

    private func performDelivery(
        _ result: SnippetTemplateEngine.ExpansionResult,
        targetApp: NSRunningApplication?,
        expectedKeyword: String?,
        keywordLength: Int,
        automaticGeneration: AutomaticGeneration?,
        onDelivered: @escaping @MainActor () -> Void
    ) async {
        guard finishPendingPasteboardOwnership(),
            await activateAndWaitForTarget(
                targetApp,
                automaticGeneration: automaticGeneration),
            deliveryIsAllowed(
                automaticGeneration: automaticGeneration,
                targetApp: targetApp,
                promptForInteractiveAccessibility: true)
        else { return }

        let completion = SnippetDeliveryCompletion(callback: onDelivered)
        let accessibilityReplacement = replaceUsingAccessibility(
            result,
            targetApp: targetApp,
            expectedKeyword: expectedKeyword,
            keywordLength: keywordLength)
        if accessibilityReplacement == .delivered {
            completion.confirm()
            return
        }
        guard accessibilityReplacement.fallsBackToEvents else { return }

        guard
            await deliverUsingEvents(
                result.text,
                keywordLength: keywordLength,
                targetApp: targetApp,
                automaticGeneration: automaticGeneration)
        else { return }

        guard let offset = result.cursorOffsetFromEnd, offset > 0 else {
            completion.confirm()
            return
        }
        for index in 0..<offset {
            guard
                deliveryIsAllowed(
                    automaticGeneration: automaticGeneration,
                    targetApp: targetApp,
                    promptForInteractiveAccessibility: false),
                postKey(code: CGKeyCode(kVK_LeftArrow), targetApp: targetApp)
            else { return }
            if index < offset - 1,
                !(await wait(for: .milliseconds(8)))
            {
                return
            }
        }
        completion.confirm()
    }

    private func deliverUsingEvents(
        _ text: String,
        keywordLength: Int,
        targetApp: NSRunningApplication?,
        automaticGeneration: AutomaticGeneration?
    ) async -> Bool {
        let isShortSingleLine =
            text.count <= 100
            && !text.contains("\n")
            && !text.contains("\r")
        if isShortSingleLine {
            return await deliverUsingUnicodeEvents(
                text,
                keywordLength: keywordLength,
                targetApp: targetApp,
                automaticGeneration: automaticGeneration)
        }

        guard let lease = beginTemporaryPasteboardLease(text) else {
            return await deliverUsingUnicodeEvents(
                text,
                keywordLength: keywordLength,
                targetApp: targetApp,
                automaticGeneration: automaticGeneration)
        }
        activePasteboardLease = lease
        defer { finish(lease) }

        guard let deletionEvents = makeDeletionEvents(count: keywordLength),
            await wait(for: .milliseconds(80)),
            lease.isOwned,
            deliveryIsAllowed(
                automaticGeneration: automaticGeneration,
                targetApp: targetApp,
                promptForInteractiveAccessibility: false),
            await postDeletionEvents(
                deletionEvents,
                targetApp: targetApp,
                automaticGeneration: automaticGeneration),
            await waitAfterKeywordDeletion(keywordLength),
            lease.isOwned,
            deliveryIsAllowed(
                automaticGeneration: automaticGeneration,
                targetApp: targetApp,
                promptForInteractiveAccessibility: false)
        else { return false }

        let stateBeforePaste = accessibilityTextState(in: targetApp)
        Paster.postCommandV(toPid: targetApp?.processIdentifier)
        return await waitForPasteConfirmation(
            previousState: stateBeforePaste,
            pasteboardLease: lease,
            targetApp: targetApp,
            automaticGeneration: automaticGeneration)
    }

    private func deliverUsingUnicodeEvents(
        _ text: String,
        keywordLength: Int,
        targetApp: NSRunningApplication?,
        automaticGeneration: AutomaticGeneration?
    ) async -> Bool {
        guard let insertionEvents = makeUnicodeEvents(text),
            let deletionEvents = makeDeletionEvents(count: keywordLength),
            deliveryIsAllowed(
                automaticGeneration: automaticGeneration,
                targetApp: targetApp,
                promptForInteractiveAccessibility: false),
            await postDeletionEvents(
                deletionEvents,
                targetApp: targetApp,
                automaticGeneration: automaticGeneration),
            await waitAfterKeywordDeletion(keywordLength),
            deliveryIsAllowed(
                automaticGeneration: automaticGeneration,
                targetApp: targetApp,
                promptForInteractiveAccessibility: false)
        else { return false }

        post(insertionEvents, targetApp: targetApp)
        return await wait(for: .milliseconds(100))
    }

    private func postDeletionEvents(
        _ events: [[CGEvent]],
        targetApp: NSRunningApplication?,
        automaticGeneration: AutomaticGeneration?
    ) async -> Bool {
        for index in events.indices {
            guard
                deliveryIsAllowed(
                    automaticGeneration: automaticGeneration,
                    targetApp: targetApp,
                    promptForInteractiveAccessibility: false)
            else { return false }
            post(events[index], targetApp: targetApp)
            if index < events.count - 1,
                !(await wait(for: .milliseconds(8)))
            {
                return false
            }
        }
        return true
    }

    private func waitAfterKeywordDeletion(_ keywordLength: Int) async -> Bool {
        if keywordLength == 0 { return true }
        return await wait(for: .milliseconds(40))
    }

    private func beginTemporaryPasteboardLease(_ text: String) -> TemporaryPasteboardLease? {
        clipboardManager.prepareForTinycastPasteboardMutation()
        return TemporaryPasteboardLease.begin(
            text: text,
            pasteboard: NSPasteboard.general
        ) { [clipboardManager] changeCount in
            clipboardManager.synchronizeAfterTinycastPasteboardMutation(
                changeCount: changeCount)
        }
    }

    @discardableResult
    private func finishPendingPasteboardOwnership() -> Bool {
        guard let lease = activePasteboardLease else { return true }
        for _ in 0..<3 where lease.isOwned { finish(lease) }
        return !lease.isOwned
    }

    private func finish(_ lease: TemporaryPasteboardLease) {
        switch lease.restoreIfOwned() {
        case .restored(let changeCount):
            // Keeps the poller from recording the restored original as a second copy.
            clipboardManager.synchronizeAfterTinycastPasteboardMutation(changeCount: changeCount)
        case .superseded:
            break
        case .failed:
            // Still ours, so leave `activePasteboardLease` in place for the retry below.
            return
        }
        if activePasteboardLease === lease { activePasteboardLease = nil }
    }

    private func deliveryIsAllowed(
        automaticGeneration: AutomaticGeneration?,
        targetApp: NSRunningApplication?,
        promptForInteractiveAccessibility: Bool
    ) -> Bool {
        if let automaticGeneration {
            guard
                automaticExpansionIsAllowed(
                    generation: automaticGeneration,
                    targetApp: targetApp),
                let targetApp,
                targetApp.isActive,
                NSWorkspace.shared.frontmostApplication?.processIdentifier
                    == targetApp.processIdentifier
            else { return false }
            return true
        }
        guard targetApp?.isTerminated != true else { return false }
        if let targetApp {
            guard targetApp.isActive,
                NSWorkspace.shared.frontmostApplication?.processIdentifier
                    == targetApp.processIdentifier
            else { return false }
        }
        return promptForInteractiveAccessibility
            ? Permissions.ensureAccessibility()
            : Permissions.isAccessibilityTrusted()
    }

    private struct AccessibilityTextState: Equatable {
        let value: String
        let selectedRange: NSRange
    }

    private func activateAndWaitForTarget(
        _ targetApp: NSRunningApplication?,
        automaticGeneration: AutomaticGeneration?
    ) async -> Bool {
        guard let targetApp else {
            return deliveryIsAllowed(
                automaticGeneration: automaticGeneration,
                targetApp: nil,
                promptForInteractiveAccessibility: false)
        }
        activate(targetApp)
        for _ in 0..<50 {
            if targetApp.isActive,
                NSWorkspace.shared.frontmostApplication?.processIdentifier
                    == targetApp.processIdentifier
            {
                return true
            }
            if let automaticGeneration,
                !automaticExpansionIsAllowed(
                    generation: automaticGeneration,
                    targetApp: targetApp)
            {
                return false
            }
            guard await wait(for: .milliseconds(20)) else { return false }
        }
        return false
    }

    private func replaceUsingAccessibility(
        _ result: SnippetTemplateEngine.ExpansionResult,
        targetApp: NSRunningApplication?,
        expectedKeyword: String?,
        keywordLength: Int
    ) -> SnippetAccessibilityReplacement {
        guard let targetApp,
            let element = focusedElement(in: targetApp),
            isAttributeSettable(kAXSelectedTextRangeAttribute, in: element),
            isAttributeSettable(kAXSelectedTextAttribute, in: element),
            let value = stringValue(in: element),
            let originalRange = selectedRange(in: element)
        else { return .unavailable }
        guard let selectedStringRange = Range(originalRange, in: value) else {
            return .rejected
        }

        let replacementRange: NSRange
        if keywordLength > 0 {
            guard originalRange.length == 0,
                let expectedKeyword,
                value[..<selectedStringRange.lowerBound].count >= keywordLength
            else { return .rejected }
            let cursor = selectedStringRange.lowerBound
            let start = value.index(cursor, offsetBy: -keywordLength)
            let actualKeyword = String(value[start..<cursor]).lowercased()
            guard actualKeyword == expectedKeyword.lowercased() else { return .rejected }
            replacementRange = NSRange(start..<cursor, in: value)
        } else {
            replacementRange = originalRange
        }

        guard setSelectedRange(replacementRange, in: element) else { return .unavailable }
        guard
            AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                result.text as CFString) == .success
        else {
            _ = setSelectedRange(originalRange, in: element)
            return .rejected
        }

        let cursorOffset = min(result.cursorOffsetFromEnd ?? 0, result.text.count)
        let cursorIndex = result.text.index(result.text.endIndex, offsetBy: -cursorOffset)
        let insertedPrefixLength = result.text[..<cursorIndex].utf16.count
        _ = setSelectedRange(
            NSRange(location: replacementRange.location + insertedPrefixLength, length: 0),
            in: element)
        return .delivered
    }

    private func waitForPasteConfirmation(
        previousState: AccessibilityTextState?,
        pasteboardLease: TemporaryPasteboardLease,
        targetApp: NSRunningApplication?,
        automaticGeneration: AutomaticGeneration?
    ) async -> Bool {
        var readStateAfterPaste = false
        for attempt in 0..<80 {
            guard pasteboardLease.isOwned,
                deliveryIsAllowed(
                    automaticGeneration: automaticGeneration,
                    targetApp: targetApp,
                    promptForInteractiveAccessibility: false)
            else { return false }

            if let previousState,
                let currentState = accessibilityTextState(in: targetApp)
            {
                readStateAfterPaste = true
                if currentState != previousState { return true }
            }
            if SnippetPasteConfirmationPolicy.acceptsUnconfirmedDelivery(
                attempt: attempt,
                hadPreviousState: previousState != nil,
                readStateAfterPaste: readStateAfterPaste)
            {
                return true
            }
            guard await wait(for: .milliseconds(25)) else { return false }
        }
        return false
    }

    private func accessibilityTextState(
        in targetApp: NSRunningApplication?
    ) -> AccessibilityTextState? {
        guard let targetApp,
            let element = focusedElement(in: targetApp),
            let value = stringValue(in: element),
            let selectedRange = selectedRange(in: element)
        else { return nil }
        return AccessibilityTextState(value: value, selectedRange: selectedRange)
    }

    private func focusedElement(in targetApp: NSRunningApplication) -> AXUIElement? {
        let application = AXUIElementCreateApplication(targetApp.processIdentifier)
        // Per element and never inherited, so the focused element needs its own against a hang.
        AXUIElementSetMessagingTimeout(application, Self.accessibilityTimeout)
        var focusedValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                application,
                kAXFocusedUIElementAttribute as CFString,
                &focusedValue) == .success,
            let focusedValue,
            CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
        else { return nil }

        let element = focusedValue as! AXUIElement
        AXUIElementSetMessagingTimeout(element, Self.accessibilityTimeout)
        return element
    }

    private func stringValue(in element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXValueAttribute as CFString,
                &value) == .success
        else { return nil }
        return value as? String
    }

    private func selectedRange(in element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                &value) == .success,
            let value,
            CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }

        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    private func setSelectedRange(_ range: NSRange, in element: AXUIElement) -> Bool {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &cfRange) else { return false }
        return AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            value) == .success
    }

    private func isAttributeSettable(_ attribute: String, in element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        guard
            AXUIElementIsAttributeSettable(
                element,
                attribute as CFString,
                &settable) == .success
        else { return false }
        return settable.boolValue
    }

    private func activate(_ targetApp: NSRunningApplication?) {
        guard targetApp?.isTerminated == false else { return }
        targetApp?.activate()
    }

    private func selectedText(in targetApp: NSRunningApplication?) -> String? {
        guard Permissions.isAccessibilityTrusted(),
            let targetApp,
            let element = focusedElement(in: targetApp)
        else { return nil }

        var selectionValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                &selectionValue) == .success
        else { return nil }
        return selectionValue as? String
    }

    private func makeUnicodeEvents(_ text: String) -> [CGEvent]? {
        guard !text.isEmpty else { return [] }
        let source = CGEventSource(stateID: .combinedSessionState)
        var characters = Array(text.utf16)
        guard
            let down = CGEvent(
                keyboardEventSource: source,
                virtualKey: 0,
                keyDown: true),
            let up = CGEvent(
                keyboardEventSource: source,
                virtualKey: 0,
                keyDown: false)
        else { return nil }

        tag(down)
        tag(up)
        down.keyboardSetUnicodeString(
            stringLength: characters.count,
            unicodeString: &characters)
        up.keyboardSetUnicodeString(
            stringLength: characters.count,
            unicodeString: &characters)
        return [down, up]
    }

    private func makeDeletionEvents(count: Int) -> [[CGEvent]]? {
        var events: [[CGEvent]] = []
        events.reserveCapacity(count)
        for _ in 0..<count {
            guard let pair = makeKeyEvents(code: CGKeyCode(kVK_Delete)) else { return nil }
            events.append(pair)
        }
        return events
    }

    private func makeKeyEvents(
        code: CGKeyCode,
        flags: CGEventFlags = []
    ) -> [CGEvent]? {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard
            let down = CGEvent(
                keyboardEventSource: source,
                virtualKey: code,
                keyDown: true),
            let up = CGEvent(
                keyboardEventSource: source,
                virtualKey: code,
                keyDown: false)
        else { return nil }
        down.flags = flags
        up.flags = flags
        tag(down)
        tag(up)
        return [down, up]
    }

    private func postKey(code: CGKeyCode, targetApp: NSRunningApplication?) -> Bool {
        guard let events = makeKeyEvents(code: code) else { return false }
        post(events, targetApp: targetApp)
        return true
    }

    private func tag(_ event: CGEvent) {
        event.setIntegerValueField(
            .eventSourceUserData,
            value: Paster.tinycastEventTag)
    }

    private func post(_ events: [CGEvent], targetApp: NSRunningApplication?) {
        for event in events { post(event, targetApp: targetApp) }
    }

    private func post(_ event: CGEvent, targetApp: NSRunningApplication?) {
        if let pid = targetApp?.processIdentifier {
            event.postToPid(pid)
        } else {
            event.post(tap: .cghidEventTap)
        }
    }

    private func wait(for duration: Duration) async -> Bool {
        do {
            try await Task.sleep(for: duration)
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}

enum SnippetPasteConfirmationPolicy {
    static func acceptsUnconfirmedDelivery(
        attempt: Int,
        hadPreviousState: Bool,
        readStateAfterPaste: Bool
    ) -> Bool {
        attempt >= 15 && (!hadPreviousState || !readStateAfterPaste)
    }
}

@MainActor
final class SnippetDeliveryQueue {
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var tail: (id: UUID, task: Task<Void, Never>)?
    private var automaticTaskID: UUID?

    var isIdle: Bool { tasks.isEmpty }

    func enqueue(
        isAutomatic: Bool,
        operation: @escaping @MainActor () async -> Void
    ) {
        let id = UUID()
        let predecessor = tail?.task
        let task = Task { @MainActor [weak self] in
            await predecessor?.value
            guard let self else { return }
            defer { self.finish(id: id) }
            guard !Task.isCancelled else { return }
            await operation()
        }
        tasks[id] = task
        tail = (id, task)
        if isAutomatic { automaticTaskID = id }
    }

    func cancelAutomatic() {
        guard let automaticTaskID else { return }
        tasks[automaticTaskID]?.cancel()
        self.automaticTaskID = nil
    }

    func cancelAll() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        tail = nil
        automaticTaskID = nil
    }

    func drain() async {
        await tail?.task.value
    }

    private func finish(id: UUID) {
        tasks.removeValue(forKey: id)
        if automaticTaskID == id { automaticTaskID = nil }
        if tail?.id == id { tail = nil }
    }
}

@MainActor
protocol SnippetPasteboardAccess: AnyObject {
    var changeCount: Int { get }
    var pasteboardItems: [NSPasteboardItem]? { get }
    @discardableResult func clearContents() -> Int
    func writeObjects(_ objects: [any NSPasteboardWriting]) -> Bool
}

extension NSPasteboard: SnippetPasteboardAccess {}

@MainActor
final class TemporaryPasteboardLease {
    enum RestoreResult: Equatable {
        case restored(changeCount: Int)
        case superseded
        case failed
    }

    private let pasteboard: any SnippetPasteboardAccess
    private let ownedChangeCount: Int
    private let originalStringData: Data
    private let temporaryItem: NSPasteboardItem
    private var isFinished = false

    var isOwned: Bool {
        !isFinished && pasteboard.changeCount == ownedChangeCount
    }

    private init(
        pasteboard: any SnippetPasteboardAccess,
        ownedChangeCount: Int,
        originalStringData: Data,
        temporaryItem: NSPasteboardItem
    ) {
        self.pasteboard = pasteboard
        self.ownedChangeCount = ownedChangeCount
        self.originalStringData = originalStringData
        self.temporaryItem = temporaryItem
    }

    static func begin(
        text: String,
        pasteboard: any SnippetPasteboardAccess,
        onMutation: (Int) -> Void = { _ in }
    ) -> TemporaryPasteboardLease? {
        guard let snapshot = PasteboardSnapshot(pasteboard: pasteboard),
            let temporaryItems = snapshot.items(replacingFirstStringWith: text),
            let originalItems = snapshot.pasteboardItems(),
            let originalStringData = snapshot.firstStringData,
            let temporaryItem = temporaryItems.first,
            pasteboard.changeCount == snapshot.changeCount
        else { return nil }

        pasteboard.clearContents()
        guard pasteboard.writeObjects(temporaryItems) else {
            if pasteboard.writeObjects(originalItems) {
                onMutation(pasteboard.changeCount)
            }
            return nil
        }
        let ownedChangeCount = pasteboard.changeCount
        onMutation(ownedChangeCount)
        return TemporaryPasteboardLease(
            pasteboard: pasteboard,
            ownedChangeCount: ownedChangeCount,
            originalStringData: originalStringData,
            temporaryItem: temporaryItem)
    }

    func restoreIfOwned() -> RestoreResult {
        guard !isFinished else { return .superseded }
        guard pasteboard.changeCount == ownedChangeCount else {
            isFinished = true
            return .superseded
        }
        guard temporaryItem.setData(originalStringData, forType: .string) else {
            if pasteboard.changeCount != ownedChangeCount {
                isFinished = true
                return .superseded
            }
            return .failed
        }
        guard pasteboard.changeCount == ownedChangeCount else {
            isFinished = true
            return .superseded
        }
        isFinished = true
        return .restored(changeCount: ownedChangeCount)
    }
}

@MainActor
struct PasteboardSnapshot {
    struct Item {
        let values: [(type: NSPasteboard.PasteboardType, data: Data)]
    }

    let items: [Item]
    let changeCount: Int

    var firstStringData: Data? {
        items.first?.values.first { $0.type == .string }?.data
    }

    init?(pasteboard: any SnippetPasteboardAccess) {
        let changeCount = pasteboard.changeCount
        var items: [Item] = []
        for pasteboardItem in pasteboard.pasteboardItems ?? [] {
            var values: [(type: NSPasteboard.PasteboardType, data: Data)] = []
            for type in pasteboardItem.types {
                guard let data = pasteboardItem.data(forType: type) else { return nil }
                values.append((type: type, data: data))
            }
            items.append(Item(values: values))
        }
        guard pasteboard.changeCount == changeCount else { return nil }
        self.items = items
        self.changeCount = changeCount
    }

    func pasteboardItems() -> [NSPasteboardItem]? {
        makePasteboardItems(firstString: nil)
    }

    func items(replacingFirstStringWith text: String) -> [NSPasteboardItem]? {
        guard firstStringData != nil else { return nil }
        return makePasteboardItems(firstString: text)
    }

    private func makePasteboardItems(firstString: String?) -> [NSPasteboardItem]? {
        var pasteboardItems: [NSPasteboardItem] = []
        pasteboardItems.reserveCapacity(items.count)
        for (index, item) in items.enumerated() {
            let pasteboardItem = NSPasteboardItem()
            if index == 0, let firstString {
                guard pasteboardItem.setString(firstString, forType: .string),
                    pasteboardItem.setData(Data(), forType: ClipboardManager.internalType)
                else { return nil }
            }
            for value in item.values where index != 0 || firstString == nil || value.type != .string {
                guard pasteboardItem.setData(value.data, forType: value.type) else { return nil }
            }
            pasteboardItems.append(pasteboardItem)
        }
        return pasteboardItems
    }
}
