import AppKit
import Testing
@testable import EdgeControl

/// What a sticky note is saved as, and whether it comes back. The note lives in
/// layout.json as base64 RTF, so this round trip is the thing standing between
/// someone's writing and an empty yellow square after an update.
/// Main-actor because the storage helpers live on a SwiftUI view type; the work
/// itself is pure string handling.
@MainActor
@Suite("Sticky note storage")
struct StickyNoteStorageTests {

    private let font = NSFont.systemFont(ofSize: 18)

    private func note(_ string: String) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: font])
    }

    private func roundTrip(_ attributed: NSAttributedString) -> NSAttributedString? {
        RichStickyTextView.fromRTF(RichStickyTextView.rtfString(attributed))
    }

    @Test("plain text survives a round trip")
    func plainText() throws {
        let restored = try #require(roundTrip(note("milk, bread, and a new kettle")))
        #expect(restored.string == "milk, bread, and a new kettle")
    }

    /// Notes get written in whatever language the person thinks in.
    @Test(
        "non-ASCII text survives",
        arguments: [
            "Saçına çiçek taksam — ğüşıöç",
            "日本語のメモ",
            "emoji ✅ 🎉 and a — dash",
        ])
    func unicodeSurvives(text: String) throws {
        let restored = try #require(roundTrip(note(text)))
        #expect(restored.string == text)
    }

    @Test("line breaks and tabs survive")
    func whitespaceSurvives() throws {
        let text = "first\n•\tbullet\n\ttabbed\n\nafter a blank line"
        let restored = try #require(roundTrip(note(text)))
        #expect(restored.string == text)
    }

    @Test("formatting survives, not just the characters")
    func formattingSurvives() throws {
        let attributed = NSMutableAttributedString(string: "normal and bold", attributes: [.font: font])
        let bold = NSFont.boldSystemFont(ofSize: 18)
        attributed.addAttribute(.font, value: bold, range: NSRange(location: 11, length: 4))

        let restored = try #require(roundTrip(attributed))
        let restoredFont = restored.attribute(.font, at: 12, effectiveRange: nil) as? NSFont
        #expect(restoredFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    @Test("heading sizes survive")
    func headingSizesSurvive() throws {
        let attributed = NSMutableAttributedString(string: "big\nsmall", attributes: [.font: font])
        attributed.addAttribute(
            .font, value: NSFont.systemFont(ofSize: 29),
            range: NSRange(location: 0, length: 3))
        let restored = try #require(roundTrip(attributed))
        let first = restored.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(first?.pointSize == 29)
    }

    /// Checkboxes are drawn attachments in the view but must not be stored as
    /// attachments: a note written before they existed, exported to RTF, or read
    /// by anything else still has to make sense.
    @Test("a checkbox is stored as a character, not an attachment")
    func checkboxStoresAsGlyph() throws {
        let attributed = NSMutableAttributedString(string: "", attributes: [.font: font])
        let unchecked = CheckboxAttachment.make(checked: false, font: font, stroke: .black, accent: .systemBlue)
        let checked = CheckboxAttachment.make(checked: true, font: font, stroke: .black, accent: .systemBlue)
        attributed.append(NSAttributedString(attachment: unchecked))
        attributed.append(note("\ttodo\n"))
        attributed.append(NSAttributedString(attachment: checked))
        attributed.append(note("\tdone"))

        let stored = RichStickyTextView.rtfString(attributed)
        let restored = try #require(RichStickyTextView.fromRTF(stored))

        #expect(restored.string.contains("☐"))
        #expect(restored.string.contains("☑"))
        #expect(restored.string.contains("\u{FFFC}") == false, "an attachment reached storage")
        #expect(restored.string.contains("todo"))
        #expect(restored.string.contains("done"))
    }

    // MARK: what a damaged note does

    @Test("an empty note stores as empty and is not an error")
    func emptyNote() {
        #expect(RichStickyTextView.rtfString(NSAttributedString(string: "")) == "")
        #expect(RichStickyTextView.fromRTF("") == nil)
    }

    /// Returning nil is what makes the caller fall back to the plain-text
    /// mirror instead of showing a blank note, so it matters that damage reads
    /// as nil rather than as an empty string.
    @Test(
        "damaged storage yields nil so the caller can fall back",
        arguments: [
            "not base64 at all!!",
            "aGVsbG8=",  // valid base64, not RTF
            "e1xydGYx",  // truncated RTF header
        ])
    func damagedStorageYieldsNil(stored: String) {
        #expect(RichStickyTextView.fromRTF(stored) == nil)
    }

    @Test("a long note survives")
    func longNote() throws {
        let text = (1...400).map { "line \($0) of a long note" }.joined(separator: "\n")
        let restored = try #require(roundTrip(note(text)))
        #expect(restored.string == text)
    }
}
