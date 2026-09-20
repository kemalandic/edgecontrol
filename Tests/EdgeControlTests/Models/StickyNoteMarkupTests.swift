import Foundation
import Testing
@testable import EdgeControl

/// Line markup is where a note editor gets fiddly: the difference between a
/// list item and a sentence that happens to start with a number, between an
/// empty item that should end the list and one that should continue it.
@Suite("Sticky note markup")
struct StickyNoteMarkupTests {

    private let box = StickyNoteMarkup.checkboxCharacter

    // MARK: recognising a marker

    @Test("the three markers are recognised")
    func markersRecognised() {
        #expect(StickyNoteMarkup.marker(of: "•\tmilk") == .bullet)
        #expect(StickyNoteMarkup.marker(of: "\(box)\tcall the bank") == .checkbox)
        #expect(StickyNoteMarkup.marker(of: "1.\tfirst") == .ordered(1))
        #expect(StickyNoteMarkup.marker(of: "12.\ttwelfth") == .ordered(12))
    }

    @Test("a plain line has no marker")
    func plainLineHasNone() {
        #expect(StickyNoteMarkup.marker(of: "just a note") == nil)
        #expect(StickyNoteMarkup.marker(of: "") == nil)
    }

    /// Where the editor draws the line between a list item and a sentence that
    /// opens with a number. The head — digits plus the dot — may be six
    /// characters, so five digits count and six do not.
    ///
    /// Worth pinning because the boundary is arbitrary and invisible: a note
    /// beginning "1998.<tab>the year everything changed" does become item 1998
    /// of a list, which is surprising but is what the editor does. Anyone
    /// changing the cap should have to change this test on purpose.
    @Test("the number in a marker may be five digits, not six")
    func markerNumberLengthLimit() {
        #expect(StickyNoteMarkup.marker(of: "1998.\tthe year") == .ordered(1998))
        #expect(StickyNoteMarkup.marker(of: "99999.\tstill a list") == .ordered(99999))
        #expect(StickyNoteMarkup.marker(of: "123456.\ttoo many digits") == nil)
        #expect(StickyNoteMarkup.marker(of: "1234567.\tfar too many") == nil)
    }

    @Test("a dot with no number before it is not a marker")
    func bareDotIsNotAMarker() {
        #expect(StickyNoteMarkup.marker(of: ".\tnothing") == nil)
        #expect(StickyNoteMarkup.marker(of: "a.\tlettered") == nil)
    }

    @Test("a marker needs its tab")
    func markerNeedsTab() {
        #expect(StickyNoteMarkup.marker(of: "• no tab here") == nil)
        #expect(StickyNoteMarkup.marker(of: "1. no tab here") == nil)
    }

    // MARK: marker length

    /// The text system measures in UTF-16, so the length has to as well — the
    /// checkbox is an attachment character, not a glyph anyone typed.
    @Test("marker length is measured the way the text system measures")
    func markerLengths() {
        #expect(StickyNoteMarkup.markerLength(of: "•\tmilk") == 2)
        #expect(StickyNoteMarkup.markerLength(of: "\(box)\tmilk") == 2)
        #expect(StickyNoteMarkup.markerLength(of: "1.\tfirst") == 3)
        #expect(StickyNoteMarkup.markerLength(of: "12.\ttwelfth") == 4)
        #expect(StickyNoteMarkup.markerLength(of: "plain") == 0)
    }

    // MARK: content after the marker

    /// Return on an empty item ends the list instead of making another empty
    /// one, so this is the check behind that behaviour.
    @Test("an item with only its marker counts as empty", arguments: [
        "•\t", "\u{FFFC}\t", "3.\t", "•\t   ",
    ])
    func emptyItems(line: String) {
        #expect(StickyNoteMarkup.hasContentAfterMarker(line) == false)
    }

    @Test("an item with text counts as filled", arguments: [
        "•\tmilk", "\u{FFFC}\tcall the bank", "3.\tthird",
    ])
    func filledItems(line: String) {
        #expect(StickyNoteMarkup.hasContentAfterMarker(line))
    }

    @Test("a line with no marker is judged on its own text")
    func unmarkedLines() {
        #expect(StickyNoteMarkup.hasContentAfterMarker("a sentence"))
        #expect(StickyNoteMarkup.hasContentAfterMarker("   ") == false)
    }

    // MARK: continuation

    @Test("bullets and checkboxes continue as themselves")
    func simpleContinuations() {
        #expect(StickyNoteMarkup.continuation(of: "•\tmilk") == .bullet)
        #expect(StickyNoteMarkup.continuation(of: "\(box)\tcall") == .checkbox)
    }

    /// A checkbox continues unchecked, never carrying the tick forward — the
    /// new item has not been done.
    @Test("a numbered item continues with the next number")
    func numberedContinuation() {
        #expect(StickyNoteMarkup.continuation(of: "3.\tthird") == .ordered(4))
        #expect(StickyNoteMarkup.continuation(of: "9.\tninth") == .ordered(10))
    }

    @Test("an unmarked line continues nothing")
    func noContinuation() {
        #expect(StickyNoteMarkup.continuation(of: "a sentence") == nil)
    }

    // MARK: renumbering

    @Test("a straight list is numbered from where it starts")
    func straightList() {
        #expect(StickyNoteMarkup.renumber([(0, 1), (0, 1), (0, 1)]) == [1, 2, 3])
        #expect(StickyNoteMarkup.renumber([(0, 5), (0, 9), (0, 2)]) == [5, 6, 7])
    }

    /// The case that motivates a counter per level. A nested list must not
    /// advance its parent, and coming back out must resume where the parent
    /// left off rather than counting every item seen.
    @Test("nesting keeps a count per level")
    func nestedList() {
        let numbers = StickyNoteMarkup.renumber([
            (0, 1),   // 1
            (1, 1),   //   1
            (1, 1),   //   2
            (0, 1),   // 2
            (0, 1),   // 3
        ])
        #expect(numbers == [1, 1, 2, 2, 3])
    }

    @Test("leaving a nested level and returning restarts it")
    func returningToANestedLevel() {
        let numbers = StickyNoteMarkup.renumber([
            (0, 1), (1, 1), (1, 1), (0, 1), (1, 1),
        ])
        #expect(numbers == [1, 1, 2, 2, 1], "the nested count should restart under the new parent")
    }

    @Test("an empty list renumbers to nothing")
    func emptyList() {
        #expect(StickyNoteMarkup.renumber([]).isEmpty)
    }

    // MARK: links

    @Test("http and https with a host are links", arguments: [
        "https://example.com", "http://example.com/path?q=1", "https://example.com:8443/x",
    ])
    func validLinks(text: String) {
        #expect(StickyNoteMarkup.isWebLink(text))
    }

    /// Narrow on purpose. A file: or javascript: URL pasted into a note is not
    /// something this editor should turn into something clickable.
    @Test("anything else is text", arguments: [
        "example.com", "ftp://example.com", "file:///etc/passwd",
        "javascript:alert(1)", "https://", "two words", "", "mailto:a@b.c",
    ])
    func nonLinks(text: String) {
        #expect(StickyNoteMarkup.isWebLink(text) == false)
    }
}
