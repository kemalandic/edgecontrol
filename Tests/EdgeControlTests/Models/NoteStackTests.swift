import Foundation
import Testing

@testable import EdgeControl

/// A stack is a list of shortcuts, not a second idea of what the widget is
/// showing — choosing a tab writes the widget's own note id. What has to hold
/// is that the strip always agrees with the note on screen, and that closing
/// a tab never takes a note with it.
@Suite("Note stack")
struct NoteStackTests {

    private let titles = ["a": "Today", "b": "Inbox", "c": "Groceries"]

    private func tabs(_ ids: [String], active: String) -> [NoteStack.Tab] {
        NoteStack.tabs(ids: ids, active: active) { titles[$0] }
    }

    @Test("The tabs are the stack, named, with the shown one lit")
    func tabsFromStack() {
        let result = tabs(["a", "b", "c"], active: "b")

        #expect(result.map(\.title) == ["Today", "Inbox", "Groceries"])
        #expect(result.map(\.isActive) == [false, true, false])
    }

    /// Otherwise pointing a stacked widget somewhere through the note picker
    /// leaves every tab unselected, with no way back to what is on screen.
    @Test("The note being shown is always a tab, even when it is not in the list")
    func activeIsAlwaysPresent() {
        let result = tabs(["a", "b"], active: "c")

        #expect(result.map(\.id) == ["a", "b", "c"])
        #expect(result.last?.isActive == true)
    }

    @Test("A note listed twice gets one tab")
    func duplicatesCollapse() {
        #expect(tabs(["a", "a", "b"], active: "a").map(\.id) == ["a", "b"])
    }

    @Test("Empty ids are not tabs")
    func emptyIdsIgnored() {
        #expect(tabs(["", "a", ""], active: "a").map(\.id) == ["a"])
        #expect(tabs([], active: "").isEmpty)
    }

    @Test("A note nobody can name still gets a tab")
    func unknownTitles() {
        let result = NoteStack.tabs(ids: ["missing"], active: "missing") { _ in nil }
        #expect(result.first?.title == "Untitled note")
    }

    /// On a cell that can be a hundred points tall, a row of chrome naming
    /// the only thing present is a row of chrome.
    @Test("One tab is not a strip")
    func stripNeedsMoreThanOne() {
        #expect(!NoteStack.showsStrip(tabs(["a"], active: "a")))
        #expect(NoteStack.showsStrip(tabs(["a", "b"], active: "a")))
        #expect(!NoteStack.showsStrip([]))
    }

    // MARK: - Editing the stack

    @Test("Adding puts a note at the end, once")
    func adding() {
        #expect(NoteStack.adding("c", to: ["a", "b"]) == ["a", "b", "c"])
        #expect(NoteStack.adding("a", to: ["a", "b"]) == ["a", "b"])
        #expect(NoteStack.adding("", to: ["a"]) == ["a"])
    }

    @Test("Removing a tab that is not the one being shown leaves the note alone")
    func removingAnInactiveTab() {
        let result = NoteStack.removing("a", from: ["a", "b", "c"], active: "b")
        #expect(result.ids == ["b", "c"])
        #expect(result.active == "b")
    }

    @Test("Removing the shown tab lands on its left-hand neighbour")
    func removingTheActiveTab() {
        let result = NoteStack.removing("b", from: ["a", "b", "c"], active: "b")
        #expect(result.ids == ["a", "c"])
        #expect(result.active == "a")
    }

    @Test("Removing the first tab lands on what is now first")
    func removingTheFirstTab() {
        let result = NoteStack.removing("a", from: ["a", "b"], active: "a")
        #expect(result.ids == ["b"])
        #expect(result.active == "b")
    }

    @Test("Removing the only tab leaves nothing shown rather than something wrong")
    func removingTheLastTab() {
        let result = NoteStack.removing("a", from: ["a"], active: "a")
        #expect(result.ids.isEmpty)
        #expect(result.active == "")
    }

    @Test("Removing something that is not there changes nothing")
    func removingAStranger() {
        let result = NoteStack.removing("z", from: ["a", "b"], active: "a")
        #expect(result.ids == ["a", "b"])
        #expect(result.active == "a")
    }
}
