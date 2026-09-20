import Foundation
import Testing

@testable import EdgeControl

/// The store holds the only copy of a note once it leaves the layout document,
/// so these cover the ways that copy can go missing rather than the happy path.
@Suite("Note store")
struct NoteStoreTests {

    private func withStore(
        policy: NoteHistoryPolicy = NoteHistoryPolicy(),
        _ body: (NoteStore, URL) throws -> Void
    ) rethrows {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NoteStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(NoteStore(directory: directory, policy: policy), directory)
    }

    private func base64(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
    }

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("A note comes back the way it went in")
    func roundTrip() {
        withStore { store, _ in
            store.save(id: "n1", rtfBase64: base64("body one"), plainText: "body one", now: start)
            #expect(store.body(id: "n1") == base64("body one"))
            #expect(store.plainText(id: "n1") == "body one")
        }
    }

    /// The index is written with one date strategy and read with another only
    /// once — and when it happens nothing throws: the read fails quietly and
    /// every note's title and history vanish while the bodies sit there intact.
    @Test("The index survives being written and read back")
    func indexSurvivesAReload() {
        withStore { store, directory in
            store.save(id: "n1", rtfBase64: base64("groceries"), plainText: "Groceries\nmilk", now: start)

            let reopened = NoteStore(directory: directory)
            let record = reopened.record(id: "n1")
            #expect(record?.title == "Groceries")
            #expect(record?.created == start)
            #expect(record?.modified == start)
            #expect(reopened.records().count == 1)
        }
    }

    @Test("Saving over a note keeps the version it replaced")
    func previousVersionIsArchived() {
        withStore { store, _ in
            store.save(id: "n1", rtfBase64: base64("v1"), plainText: "v1", now: start)
            store.save(id: "n1", rtfBase64: base64("v2"), plainText: "v2", now: start + 3_600)

            #expect(store.body(id: "n1") == base64("v2"))
            #expect(store.snapshots(id: "n1") == [start])
            #expect(store.snapshotBody(id: "n1", at: start) == base64("v1"))
        }
    }

    @Test("Saves inside the window do not each leave a copy")
    func historyIsCoalesced() {
        withStore { store, _ in
            store.save(id: "n1", rtfBase64: base64("v1"), plainText: "v1", now: start)
            store.save(id: "n1", rtfBase64: base64("v2"), plainText: "v2", now: start + 60)
            store.save(id: "n1", rtfBase64: base64("v3"), plainText: "v3", now: start + 120)
            store.save(id: "n1", rtfBase64: base64("v4"), plainText: "v4", now: start + 180)

            // One copy for the whole burst — the first thing replaced.
            #expect(store.snapshots(id: "n1") == [start])
        }
    }

    @Test("Only the most recent copies are kept")
    func historyIsPruned() {
        withStore(policy: NoteHistoryPolicy(coalescingWindow: 0, keep: 2)) { store, _ in
            for step in 0...3 {
                let at = start + Double(step) * 60
                store.save(id: "n1", rtfBase64: base64("v\(step)"), plainText: "v\(step)", now: at)
            }
            #expect(store.snapshots(id: "n1") == [start + 60, start + 120])
        }
    }

    @Test("Deleting a note takes its body, mirror, history and index entry")
    func deleteRemovesEverything() {
        withStore(policy: NoteHistoryPolicy(coalescingWindow: 0, keep: 5)) { store, directory in
            store.save(id: "n1", rtfBase64: base64("v1"), plainText: "v1", now: start)
            store.save(id: "n1", rtfBase64: base64("v2"), plainText: "v2", now: start + 60)
            store.save(id: "keep-me", rtfBase64: base64("other"), plainText: "other", now: start)

            store.delete(id: "n1")

            #expect(store.record(id: "n1") == nil)
            #expect(store.body(id: "n1") == "")
            #expect(store.snapshots(id: "n1").isEmpty)
            let fm = FileManager.default
            #expect(!fm.fileExists(atPath: directory.appendingPathComponent("n1.rtf").path))
            #expect(!fm.fileExists(atPath: directory.appendingPathComponent("n1.txt").path))
            #expect(!fm.fileExists(atPath: directory.appendingPathComponent("History/n1").path))
            // The neighbour is untouched.
            #expect(store.body(id: "keep-me") == base64("other"))
        }
    }

    @Test("Adopting a note twice does not overwrite the one already there")
    func adoptIsIdempotent() {
        withStore { store, _ in
            var config = WidgetConfig()
            config[NoteMigration.bodyKey] = .string(base64("from the layout"))
            let plan = try! #require(NoteMigration.plan(config: config, id: "n1"))

            store.adopt(plan, now: start)
            store.save(id: "n1", rtfBase64: base64("edited since"), plainText: "edited since", now: start + 60)
            store.adopt(plan, now: start + 120)

            #expect(store.body(id: "n1") == base64("edited since"))
        }
    }

    @Test("An emptied note is an empty note, not a missing one")
    func emptiedNoteKeepsItsFile() {
        withStore { store, directory in
            store.save(id: "n1", rtfBase64: base64("something"), plainText: "something", now: start)
            store.save(id: "n1", rtfBase64: "", plainText: "", now: start + 3_600)

            #expect(store.body(id: "n1") == "")
            #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("n1.rtf").path))
            #expect(store.record(id: "n1")?.title == "Untitled note")
            // What it said before is still recoverable.
            #expect(store.snapshotBody(id: "n1", at: start) == base64("something"))
        }
    }

    @Test("A note that was never saved reads as empty rather than failing")
    func unknownNote() {
        withStore { store, _ in
            #expect(store.body(id: "nope") == "")
            #expect(store.plainText(id: "nope") == "")
            #expect(store.record(id: "nope") == nil)
            #expect(store.snapshots(id: "nope").isEmpty)
            #expect(store.snapshotBody(id: "nope", at: start) == nil)
        }
    }
}
