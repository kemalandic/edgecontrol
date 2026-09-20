import AppKit
import Testing

@testable import EdgeControl

/// The formatting commands are the ones people press most and the ones that
/// were hardest to check, because they lived on the text view. Lifted off it,
/// they are what they always were: attributes changed over a range.
@Suite("Sticky note formatting")
@MainActor
struct StickyNoteFormattingTests {

    private let font = NSFont.monospacedSystemFont(ofSize: 18, weight: .regular)

    private var formatting: StickyNoteFormatting {
        StickyNoteFormatting(
            layout: StickyNoteLayout(font: font), defaultFont: font,
            defaultColor: .white, accentColor: .systemYellow)
    }

    private func storage(_ text: String) -> NSMutableAttributedString {
        NSMutableAttributedString(
            string: text, attributes: [.font: font, .foregroundColor: NSColor.white])
    }

    private func whole(_ storage: NSAttributedString) -> NSRange {
        NSRange(location: 0, length: storage.length)
    }

    private func isBold(_ storage: NSAttributedString, at index: Int) -> Bool {
        guard let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont else {
            return false
        }
        return font.fontDescriptor.symbolicTraits.contains(.bold)
    }

    // MARK: - Traits

    @Test("Bold goes on, and comes off again")
    func boldToggles() {
        let note = storage("some words")

        formatting.toggle(.bold, in: note, range: whole(note))
        #expect(isBold(note, at: 0))

        formatting.toggle(.bold, in: note, range: whole(note))
        #expect(!isBold(note, at: 0))
    }

    /// Dragging across a half-bold phrase and pressing Cmd+B should make the
    /// phrase bold, not invert it character by character.
    @Test("A half-styled selection becomes uniformly styled")
    func mixedSelectionGoesOn() {
        let note = storage("half bold")
        formatting.toggle(.bold, in: note, range: NSRange(location: 0, length: 4))

        formatting.toggle(.bold, in: note, range: whole(note))

        #expect(isBold(note, at: 0))
        #expect(isBold(note, at: note.length - 1))
    }

    @Test("Only a fully styled selection turns it off")
    func fullySelectedGoesOff() {
        let note = storage("all bold")
        formatting.toggle(.bold, in: note, range: whole(note))

        formatting.toggle(.bold, in: note, range: whole(note))

        #expect(!isBold(note, at: 0))
    }

    @Test("Italic is independent of bold")
    func traitsAreIndependent() throws {
        let note = storage("both")
        formatting.toggle(.bold, in: note, range: whole(note))
        formatting.toggle(.italic, in: note, range: whole(note))

        let styled = try #require(note.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(styled.fontDescriptor.symbolicTraits.contains(.bold))
        #expect(styled.fontDescriptor.symbolicTraits.contains(.italic))
    }

    @Test("An empty or impossible range changes nothing rather than trapping")
    func emptyRanges() {
        let note = storage("text")
        #expect(!formatting.toggle(.bold, in: note, range: NSRange(location: 0, length: 0)))
        #expect(!formatting.toggle(.bold, in: note, range: NSRange(location: 2, length: 99)))
        #expect(!formatting.toggleStrikethrough(in: note, range: NSRange(location: 99, length: 1)))
        #expect(!isBold(note, at: 0))
    }

    // MARK: - Strikethrough and code

    @Test("Strikethrough goes on and off")
    func strikethrough() {
        let note = storage("done with this")

        formatting.toggleStrikethrough(in: note, range: whole(note))
        #expect(note.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int != 0)

        formatting.toggleStrikethrough(in: note, range: whole(note))
        #expect(note.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) == nil)
    }

    /// The chip is what tells a code span from the note's own font, which is
    /// monospaced by default — so the chip is what has to come and go.
    @Test("Code puts the chip on, and takes it off")
    func codeSpan() {
        let note = storage("git status")

        formatting.toggleCode(in: note, range: whole(note))
        #expect(note.attribute(.backgroundColor, at: 0, effectiveRange: nil) != nil)

        formatting.toggleCode(in: note, range: whole(note))
        #expect(note.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil)
    }

    @Test("A code span survives the round trip through markdown")
    func codeAgreesWithTheWriter() {
        let note = storage("git status")
        formatting.toggleCode(in: note, range: whole(note))
        // One line entirely in code is written as a span, not a fence.
        #expect(NoteMarkdown.markdown(from: note, baseFont: font) == "`git status`")
    }

    // MARK: - Body text

    @Test("Body text strips what was put on, and keeps the link")
    func resetToBody() {
        let note = storage("a styled link")
        note.addAttribute(.link, value: "https://example.com", range: whole(note))
        formatting.toggle(.bold, in: note, range: whole(note))
        formatting.toggleStrikethrough(in: note, range: whole(note))

        formatting.resetToBody(in: note, range: whole(note))

        #expect(!isBold(note, at: 0))
        #expect(note.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) == nil)
        #expect(note.attribute(.underlineStyle, at: 0, effectiveRange: nil) == nil)
        // The link is the one thing worth keeping: it is content, not styling.
        #expect(note.attribute(.link, at: 0, effectiveRange: nil) != nil)
    }

    @Test("Body text puts a heading back to body size")
    func resetUndoesAHeading() throws {
        let layout = StickyNoteLayout(font: font)
        let note = storage("Title")
        note.addAttribute(.font, value: layout.headingFont(1), range: whole(note))

        formatting.resetToBody(in: note, range: whole(note))

        let restored = try #require(note.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(restored.pointSize == font.pointSize)
    }

    // MARK: - Checkboxes

    private func noteWithBoxes() -> NSMutableAttributedString {
        let note = storage(
            "\(StickyNoteMarkup.uncheckedGlyph)\tfirst\nplain line\n\(StickyNoteMarkup.checkedGlyph)\tsecond")
        StickyNoteNormalizer(
            layout: StickyNoteLayout(font: font), defaultFont: font,
            defaultColor: .white, accentColor: .systemYellow
        ).drawCheckboxes(in: note)
        return note
    }

    @Test("A selection finds every box it touches, and nothing else")
    func findsTheBoxes() {
        let note = noteWithBoxes()
        let found = formatting.checkboxLocations(in: note, range: whole(note))
        #expect(found.count == 2)
    }

    @Test("A caret finds the box on its own line only")
    func caretFindsOneBox() {
        let note = noteWithBoxes()
        let found = formatting.checkboxLocations(in: note, range: NSRange(location: 1, length: 0))
        #expect(found == [0])
    }

    @Test("A line with no box offers none")
    func plainLineHasNoBox() {
        let note = noteWithBoxes()
        let plainLine = (note.string as NSString).range(of: "plain line")
        #expect(formatting.checkboxLocations(in: note, range: plainLine).isEmpty)
    }

    /// A caret sitting after the last character is an ordinary place for it
    /// to be, and anything further is clamped there rather than trapping —
    /// so the last line is what answers, which is also what somebody
    /// pressing the key at the end of a note means.
    @Test("A range past the end is clamped to the end rather than trapping")
    func outOfRange() {
        let note = noteWithBoxes()
        let lastBox = formatting.checkboxLocations(in: note, range: whole(note)).last

        #expect(formatting.checkboxLocations(in: note, range: NSRange(location: note.length, length: 0)) == [lastBox])
        #expect(formatting.checkboxLocations(in: note, range: NSRange(location: 9_999, length: 5)) == [lastBox])
        // A location that is not a character is still refused.
        #expect(formatting.flippedCheckbox(at: 9_999, in: note) == nil)
    }

    @Test("Flipping a box turns it over")
    func flipping() throws {
        let note = noteWithBoxes()
        let flipped = try #require(formatting.flippedCheckbox(at: 0, in: note))
        let box = try #require(flipped.attribute(.attachment, at: 0, effectiveRange: nil) as? CheckboxAttachment)
        #expect(box.checked)
    }

    /// A bare box has no paragraph style, and the normalizer reads a missing
    /// one as indent level zero — so without the carry-over, ticking a nested
    /// to-do would outdent it every time.
    @Test("A flipped box keeps the indent it was standing in")
    func flippingKeepsTheIndent() throws {
        let layout = StickyNoteLayout(font: font)
        let note = noteWithBoxes()
        let nested = layout.paragraphStyle(
            isHeading: false, isList: true, markerInset: 0, level: 3)
        note.addAttribute(.paragraphStyle, value: nested, range: NSRange(location: 0, length: 1))

        let flipped = try #require(formatting.flippedCheckbox(at: 0, in: note))
        let style = try #require(
            flipped.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)

        #expect(layout.indentLevel(of: style, isList: true) == 3)
    }
}
