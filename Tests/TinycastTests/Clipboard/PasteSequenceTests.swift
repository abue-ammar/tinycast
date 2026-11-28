import Foundation
import Testing

@testable import Tinycast

@MainActor
struct PasteSequenceTests {
    let start = Date(timeIntervalSinceReferenceDate: 0)
    let newest = ClipboardItem(text: "newest", sourceBundleID: nil)
    let middle = ClipboardItem(text: "middle", sourceBundleID: nil)
    let oldest = ClipboardItem(text: "oldest", sourceBundleID: nil)
    let image = ClipboardItem(imagePath: "/scratch/shot.png", sourceBundleID: nil)
    let file = ClipboardItem(filePath: "/scratch/report.pdf", sourceBundleID: nil)
    var history: [ClipboardItem] { [newest, image, middle, file, oldest] }

    @Test func walksEveryKindNewestFirst() {
        var sequence = freshSequence()
        #expect(pasted(&sequence, from: history) == ids(history))
    }

    @Test func stopsAtTheEndRatherThanWrapping() {
        var sequence = freshSequence()
        _ = pasted(&sequence, from: history)
        #expect(sequence.next(in: history) == nil)
    }

    @Test func emptyHistoryHasNothingToPaste() {
        var sequence = PasteSequence(history: [], changeCount: 1, now: start)
        #expect(sequence.next(in: []) == nil)
    }

    @Test func promotionMidWalkNeitherRepeatsNorSkips() {
        var sequence = freshSequence()
        _ = sequence.next(in: history)
        let promoted = [middle, newest, image, file, oldest]
        #expect(pasted(&sequence, from: promoted) == ids([image, middle, file, oldest]))
    }

    @Test func captureMidWalkWaitsForTheNextWalk() {
        var sequence = freshSequence()
        let captured = [ClipboardItem(text: "captured", sourceBundleID: nil)] + history
        #expect(pasted(&sequence, from: captured) == ids(history))
    }

    @Test func entryDeletedMidWalkIsSkipped() {
        var sequence = freshSequence()
        let remaining = history.filter { $0.id != middle.id }
        #expect(pasted(&sequence, from: remaining) == ids(remaining))
    }

    @Test func clearedHistoryEndsTheWalk() {
        var sequence = freshSequence()
        _ = sequence.next(in: history)
        #expect(sequence.next(in: []) == nil)
    }

    @Test func ownPasteKeepsTheWalkGoing() {
        var sequence = freshSequence()
        sequence.recordPaste(changeCount: 4, at: start)
        #expect(sequence.continues(changeCount: 4, at: start))
    }

    @Test func newCopyEndsTheWalk() {
        var sequence = freshSequence()
        sequence.recordPaste(changeCount: 4, at: start)
        #expect(!sequence.continues(changeCount: 5, at: start))
    }

    @Test func pauseUnderTheTimeoutKeepsTheWalkGoing() {
        let later = start.addingTimeInterval(PasteSequence.idleTimeout - 1)
        #expect(freshSequence().continues(changeCount: 1, at: later))
    }

    @Test func pauseOfTheFullTimeoutEndsTheWalk() {
        let later = start.addingTimeInterval(PasteSequence.idleTimeout)
        #expect(!freshSequence().continues(changeCount: 1, at: later))
    }

    @Test func eachPasteRestartsTheTimeout() {
        var sequence = freshSequence()
        let paste = start.addingTimeInterval(PasteSequence.idleTimeout - 1)
        sequence.recordPaste(changeCount: 2, at: paste)
        #expect(
            sequence.continues(changeCount: 2, at: paste.addingTimeInterval(PasteSequence.idleTimeout - 1)))
    }

    @Test func pressInsideTheSettleIntervalIsHeldBack() {
        var sequence = freshSequence()
        sequence.recordPaste(changeCount: 2, at: start)
        let tooSoon = start.addingTimeInterval(PasteSequence.settleInterval / 2)
        #expect(sequence.isSettling(at: tooSoon))
    }

    @Test func pressAtTheSettleIntervalGoesThrough() {
        var sequence = freshSequence()
        sequence.recordPaste(changeCount: 2, at: start)
        let settled = start.addingTimeInterval(PasteSequence.settleInterval)
        #expect(!sequence.isSettling(at: settled))
    }

    private func freshSequence() -> PasteSequence {
        PasteSequence(history: history, changeCount: 1, now: start)
    }

    /// Every entry the walk pastes from `live` until it runs out.
    private func pasted(_ sequence: inout PasteSequence, from live: [ClipboardItem]) -> [UUID] {
        var pasted: [UUID] = []
        while let item = sequence.next(in: live) { pasted.append(item.id) }
        return pasted
    }

    private func ids(_ items: [ClipboardItem]) -> [UUID] { items.map(\.id) }
}
