import AppKit
import Testing

@testable import EdgeControl

/// The one-way door in the note migration: a note written before the rich
/// editor exists only as plain text, and this is the single place it is turned
/// into what the store keeps. If it drops anything, that note is gone.
@Suite("Legacy sticky notes")
@MainActor
struct StickyNoteLegacyTests {

    @Test("A widget that was never written in converts to nothing")
    func emptyStaysEmpty() {
        #expect(StickyNoteLegacy.rtfBase64(fromPlainText: "", config: WidgetConfig()).isEmpty)
    }

    @Test("Every word survives the conversion")
    func wordsSurvive() throws {
        let text = "Shopping\n- milk\n- eggs\n\n1. call the bank"
        let base64 = StickyNoteLegacy.rtfBase64(fromPlainText: text, config: WidgetConfig())
        let restored = try #require(RichStickyTextView.fromRTF(base64))

        // Verbatim: the markers a legacy note carries are its text. The editor
        // converts markup as it is typed, and nothing was typed here.
        #expect(restored.string == text)
    }

    @Test("A markdown link becomes a link")
    func linksConvert() throws {
        let base64 = StickyNoteLegacy.rtfBase64(
            fromPlainText: "see [the docs](https://example.com/guide) for more",
            config: WidgetConfig()
        )
        let restored = try #require(RichStickyTextView.fromRTF(base64))

        #expect(restored.string == "see the docs for more")
        let range = (restored.string as NSString).range(of: "the docs")
        let link = restored.attribute(.link, at: range.location, effectiveRange: nil)
        #expect(link != nil, "the link attribute did not survive the round trip")
    }

    @Test("The note is written in the size the widget was configured for")
    func configuredFontIsUsed() throws {
        var config = WidgetConfig()
        config["font"] = .string("serif")
        config["fontSize"] = .double(22)

        let base64 = StickyNoteLegacy.rtfBase64(fromPlainText: "some text", config: config)
        let restored = try #require(RichStickyTextView.fromRTF(base64))
        let font = try #require(restored.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)

        #expect(font.pointSize == 22)
    }

    @Test("A widget with no font settings still converts")
    func defaultsAreUsable() throws {
        let base64 = StickyNoteLegacy.rtfBase64(fromPlainText: "plain", config: WidgetConfig())
        let restored = try #require(RichStickyTextView.fromRTF(base64))
        let font = try #require(restored.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        // The schema default, which is what the widget would have drawn with.
        #expect(font.pointSize == 18)
    }
}
