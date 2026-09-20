import Foundation
import Testing

@testable import EdgeControl

@Suite("Note index")
struct NoteIndexTests {

    // MARK: - Titles

    @Test("A note is called after its first line that says something")
    func titleFromFirstMeaningfulLine() {
        #expect(NoteIndex.title(fromPlainText: "Grocery list\nmilk\neggs") == "Grocery list")
        #expect(NoteIndex.title(fromPlainText: "\n\n   \nStandup notes") == "Standup notes")
    }

    @Test(
        "List and heading markup is not part of the name",
        arguments: [
            ("•\tcall the bank", "call the bank"),
            ("☐\tpay rent", "pay rent"),
            ("☑\tpay rent", "pay rent"),
            ("1.\tfirst thing", "first thing"),
            ("## Standup", "Standup"),
            ("### Deploy checklist", "Deploy checklist"),
        ])
    func titleStripsMarkup(line: String, expected: String) {
        #expect(NoteIndex.title(fromPlainText: line) == expected)
    }

    @Test("An empty note still has something to call it")
    func titleFallback() {
        #expect(NoteIndex.title(fromPlainText: "") == "Untitled note")
        #expect(NoteIndex.title(fromPlainText: "\n  \n\t\n") == "Untitled note")
        #expect(NoteIndex.title(fromPlainText: "", fallback: "New note") == "New note")
    }

    @Test("A long first line is cut on a word boundary")
    func titleTruncation() {
        let line = "The quarterly planning meeting has been moved to Thursday afternoon in the big room"
        let title = NoteIndex.title(fromPlainText: line)
        #expect(title.count <= 61)  // the limit, plus the ellipsis
        #expect(title.hasSuffix("…"))
        #expect(!title.dropLast().hasSuffix(" "))
        // Cut between words, so the last word is whole.
        let lastWord = title.dropLast().split(separator: " ").last.map(String.init) ?? ""
        #expect(line.contains(lastWord))
    }

    @Test("A long first line with no early space is cut anyway")
    func titleTruncationWithoutSpaces() {
        let line = String(repeating: "x", count: 200)
        let title = NoteIndex.title(fromPlainText: line)
        #expect(title.count == 61)
        #expect(title.hasSuffix("…"))
    }

    // MARK: - The index

    @Test("Touching a note creates it once and updates it after")
    func touchCreatesThenUpdates() {
        let created = Date(timeIntervalSince1970: 1_000)
        let edited = Date(timeIntervalSince1970: 2_000)
        var index = NoteIndex()

        index.touch(id: "a", title: "First", at: created)
        #expect(index["a"]?.created == created)
        #expect(index["a"]?.modified == created)

        index.touch(id: "a", title: "Second", at: edited)
        #expect(index.count == 1)
        #expect(index["a"]?.title == "Second")
        // When it was written is not when it was made.
        #expect(index["a"]?.created == created)
        #expect(index["a"]?.modified == edited)
    }

    @Test("Removing a note takes it out of the index")
    func removal() {
        var index = NoteIndex()
        index.touch(id: "a", title: "A", at: Date())
        index.touch(id: "b", title: "B", at: Date())
        #expect(index.remove(id: "a")?.title == "A")
        #expect(index["a"] == nil)
        #expect(index.count == 1)
        #expect(index.remove(id: "missing") == nil)
    }

    @Test("Notes list most recently edited first, and ties do not shuffle")
    func ordering() {
        let old = Date(timeIntervalSince1970: 1_000)
        let new = Date(timeIntervalSince1970: 2_000)
        var index = NoteIndex()
        index.touch(id: "b", title: "B", at: new)
        index.touch(id: "a", title: "A", at: new)
        index.touch(id: "c", title: "C", at: old)

        #expect(index.mostRecentFirst.map(\.id) == ["a", "b", "c"])
        // Same input, same order — a list that reorders itself between two
        // renders is worse than one in the wrong order.
        #expect(index.mostRecentFirst.map(\.id) == index.mostRecentFirst.map(\.id))
    }

    @Test("An index survives a round trip through JSON")
    func codableRoundTrip() throws {
        var index = NoteIndex()
        index.touch(id: "a", title: "Groceries", at: Date(timeIntervalSince1970: 1_234))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(NoteIndex.self, from: encoder.encode(index))
        #expect(restored == index)
    }
}
