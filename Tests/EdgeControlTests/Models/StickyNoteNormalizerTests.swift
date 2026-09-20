import AppKit
import Testing

@testable import EdgeControl

/// These passes run on every keystroke and on every load, which makes them
/// the code most likely to be wrong — and until they were lifted off the text
/// view, the code least possible to check: reaching them needed an
/// NSTextStorage inside a window.
@Suite("Sticky note normalizer")
@MainActor
struct StickyNoteNormalizerTests {

    private let font = NSFont.monospacedSystemFont(ofSize: 18, weight: .regular)

    private var normalizer: StickyNoteNormalizer {
        StickyNoteNormalizer(
            layout: StickyNoteLayout(font: font), defaultFont: font,
            defaultColor: .white, accentColor: .systemYellow)
    }

    private func storage(_ text: String) -> NSMutableAttributedString {
        NSMutableAttributedString(
            string: text, attributes: [.font: font, .foregroundColor: NSColor.white])
    }

    private func attachments(in storage: NSAttributedString) -> [CheckboxAttachment] {
        var found: [CheckboxAttachment] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if let box = value as? CheckboxAttachment { found.append(box) }
        }
        return found
    }

    // MARK: - Drawing

    /// The file keeps characters so it means something to anything else that
    /// opens it; the view draws boxes. Every load crosses this line.
    @Test("Checkbox glyphs become drawn boxes, keeping which is ticked")
    func glyphsBecomeAttachments() {
        let note = storage("\(StickyNoteMarkup.uncheckedGlyph)\tto do\n\(StickyNoteMarkup.checkedGlyph)\tdone")

        normalizer.drawCheckboxes(in: note)

        #expect(attachments(in: note).map(\.checked) == [false, true])
        #expect(!note.string.contains(StickyNoteMarkup.uncheckedGlyph))
        #expect(!note.string.contains(StickyNoteMarkup.checkedGlyph))
    }

    @Test("A note with no boxes is left as it was")
    func nothingToDraw() {
        let note = storage("just prose\nand more prose")
        normalizer.drawCheckboxes(in: note)
        #expect(note.string == "just prose\nand more prose")
    }

    @Test("Many boxes all convert, whatever their position")
    func manyBoxes() {
        // The pass runs backwards because each replacement shifts everything
        // after it; a forwards pass drops boxes after the first.
        let lines = (1...8).map { "\(StickyNoteMarkup.uncheckedGlyph)\titem \($0)" }
        let note = storage(lines.joined(separator: "\n"))

        normalizer.drawCheckboxes(in: note)

        #expect(attachments(in: note).count == 8)
    }

    @Test("An image link becomes a drawn image when its file is there")
    func mediaIsDrawn() throws {
        // A real image, drawn rather than faked: MediaAttachment only makes
        // one when NSImage can read the bytes, so a magic-number stub would
        // test nothing.
        let drawn = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            NSColor.systemTeal.setFill()
            rect.fill()
            return true
        }
        let tiff = try #require(drawn.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiff))
        let bytes = try #require(rep.representation(using: .png, properties: [:]))

        let note = storage("shot.png")
        note.addAttribute(
            .link, value: NoteMedia.link(forFile: "shot.png"),
            range: NSRange(location: 0, length: note.length))

        var drawer = normalizer
        drawer.readMedia = { $0 == "shot.png" ? bytes : nil }
        drawer.drawMedia(in: note)

        let attachment = note.attribute(.attachment, at: 0, effectiveRange: nil) as? MediaAttachment
        #expect(attachment?.filename == "shot.png")
    }

    @Test("An image whose file is gone stays as the text naming it")
    func missingMediaStaysText() {
        let note = storage("shot.png")
        note.addAttribute(
            .link, value: NoteMedia.link(forFile: "shot.png"),
            range: NSRange(location: 0, length: note.length))

        var drawer = normalizer
        drawer.readMedia = { _ in nil }
        drawer.drawMedia(in: note)

        #expect(note.string == "shot.png")
        #expect(note.attribute(.attachment, at: 0, effectiveRange: nil) == nil)
    }

    @Test("An ordinary link is not an image")
    func ordinaryLinksAreLeftAlone() {
        let note = storage("the docs")
        note.addAttribute(
            .link, value: "https://example.com", range: NSRange(location: 0, length: note.length))

        var drawer = normalizer
        drawer.readMedia = { _ in Data([0x89, 0x50, 0x4E, 0x47]) }
        drawer.drawMedia(in: note)

        #expect(note.attribute(.attachment, at: 0, effectiveRange: nil) == nil)
    }

    // MARK: - Renumbering

    @Test("A list numbers itself in order, whatever was typed")
    func renumbering() {
        let note = storage("1.\tfirst\n5.\tsecond\n9.\tthird")
        normalizer.renumberOrderedLists(in: note)
        #expect(note.string == "1.\tfirst\n2.\tsecond\n3.\tthird")
    }

    /// A list may start anywhere — somebody continuing a numbered list from
    /// a document meant to start at seven.
    @Test("The first number of a block is kept as typed")
    func firstNumberIsKept() {
        let note = storage("7.\tseventh\n7.\teighth")
        normalizer.renumberOrderedLists(in: note)
        #expect(note.string == "7.\tseventh\n8.\teighth")
    }

    @Test("Prose between lists starts the numbering again")
    func proseResetsTheCount() {
        let note = storage("1.\tfirst\n2.\tsecond\n\n4.\tafter the gap")
        normalizer.renumberOrderedLists(in: note)
        #expect(note.string.hasSuffix("4.\tafter the gap"))
    }

    @Test("Bullets among numbers do not break the count")
    func bulletsDoNotReset() {
        let note = storage("1.\tfirst\n•\ta note about it\n3.\tsecond")
        normalizer.renumberOrderedLists(in: note)
        #expect(note.string.hasSuffix("2.\tsecond"))
    }

    @Test("An empty note is answered rather than trapped")
    func emptyStorage() {
        let note = storage("")
        normalizer.normalize(note)
        #expect(note.length == 0)
    }

    // MARK: - Legacy notes

    /// Notes written before the tab separator used a non-breaking space.
    /// They are still out there, and this is where they pick up the aligned
    /// list column.
    @Test("A pre-tab note gains its tab")
    func legacySeparatorsMigrate() {
        let note = storage("•\u{00A0}an old bullet")
        normalizer.applyParagraphSpacing(to: note)
        #expect(note.string == "•\tan old bullet")
    }

    // MARK: - Geometry

    @Test("A list line is given the hanging indent its marker needs")
    func listGeometry() throws {
        let note = storage("•\tsomething")
        normalizer.applyParagraphSpacing(to: note)

        let style = try #require(
            note.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        // Wrapped lines hang under the text, not under the bullet.
        #expect(style.headIndent > 0)
        #expect(style.tabStops.first != nil)
    }

    @Test("An indent level survives being restamped")
    func indentLevelRoundTrips() throws {
        let layout = StickyNoteLayout(font: font)
        let note = storage("•\tnested")
        note.addAttribute(
            .paragraphStyle,
            value: layout.paragraphStyle(
                isHeading: false, isList: true, markerInset: layout.markerInset(for: "•\t"), level: 2),
            range: NSRange(location: 0, length: note.length))

        normalizer.applyParagraphSpacing(to: note)

        let style = try #require(
            note.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(layout.indentLevel(of: style, isList: true) == 2)
    }

    @Test("A bigger first character makes the line a heading")
    func headingGeometry() throws {
        let note = storage("Title")
        note.addAttribute(
            .font, value: StickyNoteLayout(font: font).headingFont(1),
            range: NSRange(location: 0, length: note.length))

        normalizer.applyParagraphSpacing(to: note)

        let style = try #require(
            note.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        // Headings breathe more above than body text does.
        #expect(style.paragraphSpacingBefore > 0)
    }

    // MARK: - Together

    @Test("A whole pass leaves a note drawn, spaced and numbered")
    func fullPass() {
        let note = storage(
            "\(StickyNoteMarkup.uncheckedGlyph)\tto do\n9.\tfirst\n9.\tsecond")

        normalizer.normalize(note)

        #expect(attachments(in: note).count == 1)
        #expect(note.string.hasSuffix("9.\tfirst\n10.\tsecond"))
        #expect(note.attribute(.paragraphStyle, at: 0, effectiveRange: nil) != nil)
    }
}
