import Foundation
import Testing

@testable import EdgeControl

@Suite("Note history policy")
struct NoteHistoryPolicyTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("The first thing a note replaces is always kept")
    func firstReplacementIsArchived() {
        let policy = NoteHistoryPolicy()
        let decision = policy.decide(existing: [], outgoingModified: now - 30, now: now)
        #expect(decision.archive == now - 30)
        #expect(decision.discard.isEmpty)
    }

    @Test("A copy inside the window is enough for that window")
    func coalescing() {
        let policy = NoteHistoryPolicy(coalescingWindow: 600, keep: 20)
        let recent = policy.decide(existing: [now - 60], outgoingModified: now - 5, now: now)
        #expect(recent.archive == nil)
        #expect(recent.changesNothing)

        let stale = policy.decide(existing: [now - 900], outgoingModified: now - 5, now: now)
        #expect(stale.archive == now - 5)
    }

    @Test("A stamp already on disk is not written twice")
    func duplicateStamp() {
        let policy = NoteHistoryPolicy(coalescingWindow: 0, keep: 20)
        let decision = policy.decide(existing: [now - 100], outgoingModified: now - 100, now: now)
        #expect(decision.archive == nil)
    }

    @Test("Copies past the limit are the oldest ones")
    func pruning() {
        let policy = NoteHistoryPolicy(coalescingWindow: 0, keep: 3)
        let existing = [now - 400, now - 300, now - 200]
        let decision = policy.decide(existing: existing, outgoingModified: now - 100, now: now)
        #expect(decision.archive == now - 100)
        #expect(decision.discard == [now - 400])
    }

    @Test("Lowering the limit clears out what no longer fits, without a new copy")
    func pruningWithoutArchiving() {
        let policy = NoteHistoryPolicy(coalescingWindow: 600, keep: 2)
        // Inside the window, so nothing new is written — but four copies are
        // two too many for the limit that is now in force.
        let existing = [now - 400, now - 300, now - 200, now - 60]
        let decision = policy.decide(existing: existing, outgoingModified: now - 10, now: now)
        #expect(decision.archive == nil)
        #expect(decision.discard == [now - 400, now - 300])
    }

    @Test("History off keeps nothing and clears what is there")
    func historyDisabled() {
        let policy = NoteHistoryPolicy(coalescingWindow: 600, keep: 0)
        let decision = policy.decide(existing: [now - 100, now - 50], outgoingModified: now, now: now)
        #expect(decision.archive == nil)
        #expect(decision.discard == [now - 100, now - 50])
    }

    /// Writing a file and deleting it in the same breath is work for nothing,
    /// and it leaves a note looking as though it has history when it does not.
    @Test("A copy that would be pruned immediately is not written")
    func archiveThatWouldNotSurvive() {
        let policy = NoteHistoryPolicy(coalescingWindow: 0, keep: 1)
        let decision = policy.decide(existing: [now - 50], outgoingModified: now - 500, now: now)
        #expect(decision.archive == nil)
        #expect(decision.discard.isEmpty)
        #expect(decision.changesNothing)
    }

    @Test("Stamps arrive in any order and are treated by age, not position")
    func unorderedInput() {
        let policy = NoteHistoryPolicy(coalescingWindow: 0, keep: 2)
        let shuffled = [now - 100, now - 900, now - 500]
        let decision = policy.decide(existing: shuffled, outgoingModified: now - 10, now: now)
        #expect(decision.archive == now - 10)
        #expect(decision.discard == [now - 900, now - 500])
    }
}
