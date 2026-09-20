import Foundation
import Testing

@testable import EdgeControl

/// The digest crosses a sandbox: what it produces is all the desktop widget
/// will ever know about the note, and the widget cannot go back and ask. So
/// what matters is that the right lines cross, in an order worth glancing at.
@Suite("Note digest")
struct NoteDigestTests {

    private func plain(_ lines: [String]) -> String {
        lines.joined(separator: "\n")
    }

    private func todo(_ text: String, done: Bool = false) -> String {
        (done ? StickyNoteMarkup.checkedGlyph : StickyNoteMarkup.uncheckedGlyph) + "\t" + text
    }

    @Test("Only the to-dos cross")
    func onlyCheckboxLines() {
        let items = NoteDigest.items(
            fromPlainText: plain([
                "Shopping",
                todo("milk"),
                "• a bullet",
                "1.\tnumbered",
                "a sentence",
                todo("bread", done: true),
            ]))

        // A note's prose is what makes it a note, and none of it belongs on a
        // desktop tile.
        #expect(items.map(\.text) == ["milk", "bread"])
    }

    @Test("What is left to do comes first")
    func unfinishedFirst() {
        let items = NoteDigest.items(
            fromPlainText: plain([
                todo("done one", done: true),
                todo("still to do"),
                todo("done two", done: true),
                todo("also to do"),
            ]))

        #expect(items.map(\.text) == ["still to do", "also to do", "done one", "done two"])
        #expect(items.map(\.done) == [false, false, true, true])
    }

    @Test("Each group keeps the order the note has it in")
    func orderWithinGroups() {
        let items = NoteDigest.items(fromPlainText: plain([todo("a"), todo("b"), todo("c")]))
        #expect(items.map(\.text) == ["a", "b", "c"])
    }

    @Test("A long list is cut, and the unfinished survive the cut")
    func limitKeepsWhatMatters() {
        var lines = (1...10).map { todo("done \($0)", done: true) }
        lines.append(todo("the one thing left"))

        let items = NoteDigest.items(fromPlainText: plain(lines), limit: 3)

        #expect(items.count == 3)
        #expect(items.first?.text == "the one thing left")
    }

    @Test("A marker with nothing after it is not an item")
    func emptyItems() {
        #expect(NoteDigest.items(fromPlainText: plain([todo(""), todo("   ")])).isEmpty)
    }

    @Test("A note with no to-dos digests to nothing, rather than to noise")
    func noTodos() {
        #expect(NoteDigest.items(fromPlainText: "Just some prose.\nAnd another line.").isEmpty)
        #expect(NoteDigest.items(fromPlainText: "").isEmpty)
    }

    @Test("A limit of nothing yields nothing rather than trapping")
    func zeroLimit() {
        #expect(NoteDigest.items(fromPlainText: plain([todo("milk")]), limit: 0).isEmpty)
    }

    @Test("Items carry distinct identities, so the widget can list them")
    func identitiesAreDistinct() {
        let items = NoteDigest.items(fromPlainText: plain([todo("a"), todo("b"), todo("c")]))
        #expect(Set(items.map(\.id)).count == items.count)
    }

    @Test("Progress counts what is done against what there is")
    func progressLine() {
        let items = NoteDigest.items(
            fromPlainText: plain([todo("a", done: true), todo("b"), todo("c", done: true)]))
        #expect(NoteDigest.progress(items) == "2/3")
        #expect(NoteDigest.progress([]) == nil)
    }

    /// The tile and the note must not disagree about how many things are
    /// left, which is why the arithmetic lives on the shared item rather than
    /// once on each side of the sandbox.
    @Test("Both sides of the sandbox count the same way")
    func oneCount() {
        let items = NoteDigest.items(
            fromPlainText: plain([todo("a", done: true), todo("b"), todo("c")]))
        #expect(NoteDigest.progress(items) == WidgetNoteItem.progress(items))
        #expect(WidgetNoteItem.progress(items) == "1/3")
    }

    @Test("A note the editor wrote digests the same as one typed by hand")
    func matchesTheEditorsOwnOutput() {
        // The stored form is what the plain-text mirror holds, which is what
        // the bridge reads — so the digest has to agree with the converter.
        let attributed = NoteMarkdown.attributed(
            fromMarkdown: "# Today\n- [x] shipped\n- [ ] write it up",
            baseFont: .monospacedSystemFont(ofSize: 18, weight: .regular),
            textColor: .white)

        let items = NoteDigest.items(fromPlainText: attributed.string)

        #expect(items.map(\.text) == ["write it up", "shipped"])
        #expect(items.map(\.done) == [false, true])
    }
}
