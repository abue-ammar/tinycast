// Standalone test for Paste Sequentially's walk, compiling the real source rather than a copy.
import Foundation

@main
@MainActor
struct PasteSequenceTests {
    static var failures = 0
    static var passes = 0

    static let start = Date(timeIntervalSinceReferenceDate: 0)
    static let newest = ClipboardItem(text: "newest", sourceBundleID: nil)
    static let middle = ClipboardItem(text: "middle", sourceBundleID: nil)
    static let oldest = ClipboardItem(text: "oldest", sourceBundleID: nil)
    static let image = ClipboardItem(imagePath: "/scratch/shot.png", sourceBundleID: nil)
    static let file = ClipboardItem(filePath: "/scratch/report.pdf", sourceBundleID: nil)
    static let history = [newest, image, middle, file, oldest]

    static func main() {
        walksEveryKindNewestFirst()
        stopsAtTheEndRatherThanWrapping()
        emptyHistoryHasNothingToPaste()
        promotionMidWalkNeitherRepeatsNorSkips()
        captureMidWalkWaitsForTheNextWalk()
        entryDeletedMidWalkIsSkipped()
        clearedHistoryEndsTheWalk()
        ownPasteKeepsTheWalkGoing()
        newCopyEndsTheWalk()
        pauseUnderTheTimeoutKeepsTheWalkGoing()
        pauseOfTheFullTimeoutEndsTheWalk()
        eachPasteRestartsTheTimeout()
        pressInsideTheSettleIntervalIsHeldBack()
        pressAtTheSettleIntervalGoesThrough()

        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    static func walksEveryKindNewestFirst() {
        var sequence = freshSequence()
        expect(
            pasted(&sequence, from: history) == ids(history),
            "the walk pastes text, images and files alike, newest first")
    }

    static func stopsAtTheEndRatherThanWrapping() {
        var sequence = freshSequence()
        _ = pasted(&sequence, from: history)
        expect(sequence.next(in: history) == nil, "a press past the oldest entry pastes nothing")
    }

    static func emptyHistoryHasNothingToPaste() {
        var sequence = PasteSequence(history: [], changeCount: 1, now: start)
        expect(sequence.next(in: []) == nil, "an empty history has nothing to paste")
    }

    static func promotionMidWalkNeitherRepeatsNorSkips() {
        var sequence = freshSequence()
        _ = sequence.next(in: history)
        let promoted = [middle, newest, image, file, oldest]
        expect(
            pasted(&sequence, from: promoted) == ids([image, middle, file, oldest]),
            "a promoted entry neither repeats nor jumps the walk")
    }

    static func captureMidWalkWaitsForTheNextWalk() {
        var sequence = freshSequence()
        let captured = [ClipboardItem(text: "captured", sourceBundleID: nil)] + history
        expect(
            pasted(&sequence, from: captured) == ids(history),
            "an entry captured mid-walk is not pasted by it")
    }

    static func entryDeletedMidWalkIsSkipped() {
        var sequence = freshSequence()
        let remaining = history.filter { $0.id != middle.id }
        expect(
            pasted(&sequence, from: remaining) == ids(remaining),
            "an entry deleted mid-walk is skipped rather than pasted")
    }

    static func clearedHistoryEndsTheWalk() {
        var sequence = freshSequence()
        _ = sequence.next(in: history)
        expect(sequence.next(in: []) == nil, "clearing the history ends the walk")
    }

    static func ownPasteKeepsTheWalkGoing() {
        var sequence = freshSequence()
        sequence.recordPaste(changeCount: 4, at: start)
        expect(
            sequence.continues(changeCount: 4, at: start),
            "the count our own paste left keeps the walk going")
    }

    static func newCopyEndsTheWalk() {
        var sequence = freshSequence()
        sequence.recordPaste(changeCount: 4, at: start)
        expect(!sequence.continues(changeCount: 5, at: start), "a copy since the last paste ends the walk")
    }

    static func pauseUnderTheTimeoutKeepsTheWalkGoing() {
        let later = start.addingTimeInterval(PasteSequence.idleTimeout - 1)
        expect(
            freshSequence().continues(changeCount: 1, at: later),
            "a pause under the timeout keeps the walk going")
    }

    static func pauseOfTheFullTimeoutEndsTheWalk() {
        let later = start.addingTimeInterval(PasteSequence.idleTimeout)
        expect(
            !freshSequence().continues(changeCount: 1, at: later),
            "a pause of the full timeout ends the walk")
    }

    static func eachPasteRestartsTheTimeout() {
        var sequence = freshSequence()
        let paste = start.addingTimeInterval(PasteSequence.idleTimeout - 1)
        sequence.recordPaste(changeCount: 2, at: paste)
        expect(
            sequence.continues(changeCount: 2, at: paste.addingTimeInterval(PasteSequence.idleTimeout - 1)),
            "the timeout counts from the last paste, not the first press")
    }

    static func pressInsideTheSettleIntervalIsHeldBack() {
        var sequence = freshSequence()
        sequence.recordPaste(changeCount: 2, at: start)
        let tooSoon = start.addingTimeInterval(PasteSequence.settleInterval / 2)
        expect(sequence.isSettling(at: tooSoon), "a press before the last ⌘V can land is held back")
    }

    static func pressAtTheSettleIntervalGoesThrough() {
        var sequence = freshSequence()
        sequence.recordPaste(changeCount: 2, at: start)
        let settled = start.addingTimeInterval(PasteSequence.settleInterval)
        expect(!sequence.isSettling(at: settled), "a press once the last paste has landed goes through")
    }

    static func freshSequence() -> PasteSequence {
        PasteSequence(history: history, changeCount: 1, now: start)
    }

    /// Every entry the walk pastes from `live` until it runs out.
    static func pasted(_ sequence: inout PasteSequence, from live: [ClipboardItem]) -> [UUID] {
        var pasted: [UUID] = []
        while let item = sequence.next(in: live) { pasted.append(item.id) }
        return pasted
    }

    static func ids(_ items: [ClipboardItem]) -> [UUID] { items.map(\.id) }

    static func expect(_ condition: Bool, _ label: String) {
        if condition {
            passes += 1
        } else {
            print("FAIL: \(label)")
            failures += 1
        }
    }
}
