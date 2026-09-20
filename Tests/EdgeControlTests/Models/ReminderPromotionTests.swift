import AppKit
import Testing

@testable import EdgeControl

/// Promotion writes to the system's Reminders database, which is the one
/// place this app can leave something behind that outlives it. What has to be
/// right is which lines go — and how many times.
@Suite("Reminder promotion")
@MainActor
struct ReminderPromotionTests {

    private let base = NSFont.monospacedSystemFont(ofSize: 18, weight: .regular)

    private func note(_ markdown: String) -> NSAttributedString {
        NoteMarkdown.attributed(fromMarkdown: markdown, baseFont: base, textColor: .white)
    }

    private func wholeNote(_ markdown: String) -> [String] {
        let attributed = note(markdown)
        return ReminderPromotion.candidates(
            in: attributed, range: NSRange(location: 0, length: attributed.length))
    }

    // MARK: - Which lines

    @Test("Unfinished to-dos go, and nothing else does")
    func onlyUnfinishedCheckboxes() {
        let titles = wholeNote(
            """
            # Today
            - [ ] call the bank
            - [x] already done
            - a bullet, not a to-do
            1. numbered, not a to-do
            just a sentence
            - [ ] post the letter
            """)

        #expect(titles == ["call the bank", "post the letter"])
    }

    /// Nobody needs reminding of something they have done, and a note is
    /// mostly finished items by the end of a day.
    @Test("A finished to-do is left alone")
    func checkedItemsAreSkipped() {
        #expect(wholeNote("- [x] shipped it").isEmpty)
    }

    @Test("A marker with nothing after it is not a to-do yet")
    func emptyItemsAreSkipped() {
        let attributed = NSAttributedString(
            string: StickyNoteMarkup.uncheckedGlyph + "\t",
            attributes: [.font: base, .foregroundColor: NSColor.white])
        #expect(
            ReminderPromotion.candidates(
                in: attributed, range: NSRange(location: 0, length: attributed.length)
            ).isEmpty)
    }

    @Test("A caret promotes the line it is on, not the whole note")
    func caretTakesOneLine() {
        let attributed = note("- [ ] first\n- [ ] second\n- [ ] third")
        let secondLine = (attributed.string as NSString).range(of: "second")

        let titles = ReminderPromotion.candidates(
            in: attributed, range: NSRange(location: secondLine.location, length: 0))

        #expect(titles == ["second"])
    }

    @Test("A selection promotes every to-do it touches")
    func selectionTakesWhatItCovers() {
        let attributed = note("- [ ] first\n- [ ] second\n- [ ] third")
        let text = attributed.string as NSString
        let from = text.range(of: "first").location
        let to = text.range(of: "second")

        let titles = ReminderPromotion.candidates(
            in: attributed, range: NSRange(location: from, length: to.location + to.length - from))

        #expect(titles == ["first", "second"])
    }

    @Test("An empty note has nothing to promote")
    func emptyNote() {
        #expect(
            ReminderPromotion.candidates(in: NSAttributedString(), range: NSRange(location: 0, length: 0))
                .isEmpty)
    }

    /// A caret at the very end of a note is an ordinary place for it to be.
    @Test("A range past the end is answered rather than trapped")
    func outOfRangeSelection() {
        let attributed = note("- [ ] only")
        let past = NSRange(location: attributed.length, length: 0)
        #expect(ReminderPromotion.candidates(in: attributed, range: past) == ["only"])

        let absurd = NSRange(location: attributed.length + 50, length: 100)
        #expect(ReminderPromotion.candidates(in: attributed, range: absurd).isEmpty == false)
    }

    /// The editor draws checkboxes rather than storing them as characters, so
    /// the live note and the saved note look different to this code.
    @Test("A drawn checkbox is read the same as a stored one")
    func drawnCheckboxes() {
        let drawn = NSMutableAttributedString()
        for (checked, title) in [(false, "undone"), (true, "done")] {
            let box = CheckboxAttachment.make(
                checked: checked, font: base, stroke: .white, accent: .systemYellow)
            let line = NSMutableAttributedString(attachment: box)
            line.append(
                NSAttributedString(
                    string: "\t\(title)\n", attributes: [.font: base, .foregroundColor: NSColor.white]))
            drawn.append(line)
        }

        let titles = ReminderPromotion.candidates(
            in: drawn, range: NSRange(location: 0, length: drawn.length))

        #expect(titles == ["undone"])
    }

    // MARK: - How many times

    @Test("What is already in Reminders is not added again")
    func duplicatesAreSkipped() {
        let fresh = ReminderPromotion.newTitles(
            ["call the bank", "post the letter"], existing: ["Call the Bank", "something else"])
        #expect(fresh == ["post the letter"])
    }

    @Test("Matching ignores case and surrounding space")
    func matchingIsForgiving() {
        #expect(ReminderPromotion.newTitles(["  Milk "], existing: ["milk"]).isEmpty)
    }

    @Test("A note listing the same thing twice adds it once")
    func duplicatesWithinTheSelection() {
        #expect(ReminderPromotion.newTitles(["milk", "MILK", "bread"], existing: []) == ["milk", "bread"])
    }

    @Test("Nothing in Reminders means everything goes")
    func emptyReminders() {
        #expect(ReminderPromotion.newTitles(["a", "b"], existing: []) == ["a", "b"])
    }

    // MARK: - What it says

    @Test(
        "The result is reported in words, because nothing on the panel changes",
        arguments: [
            (0, 0, "No unfinished to-do on this line"),
            (1, 0, "Added to Reminders"),
            (3, 0, "3 added to Reminders"),
            (0, 1, "Already in Reminders"),
            (0, 4, "All 4 already in Reminders"),
            (2, 1, "2 added, 1 already there"),
        ])
    func summaries(added: Int, skipped: Int, expected: String) {
        #expect(ReminderPromotion.summary(added: added, skipped: skipped) == expected)
    }
}
