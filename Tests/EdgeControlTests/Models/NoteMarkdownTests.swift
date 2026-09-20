import AppKit
import Testing

@testable import EdgeControl

/// Markdown is the only shape a note takes that something other than this app
/// will read, so the test that matters is the round trip: text goes out, comes
/// back, and says the same thing. A converter that only writes can drift
/// without anyone noticing until an exported note fails to import.
@Suite("Note markdown")
struct NoteMarkdownTests {

    private let base = NSFont.monospacedSystemFont(ofSize: 18, weight: .regular)

    private func roundTrip(_ markdown: String) -> String {
        let attributed = NoteMarkdown.attributed(fromMarkdown: markdown, baseFont: base, textColor: .white)
        return NoteMarkdown.markdown(from: attributed, baseFont: base)
    }

    // MARK: - Block structure

    @Test(
        "Every line kind survives the round trip",
        arguments: [
            "# First level",
            "## Second level",
            "### Third level",
            "- a bullet",
            "- [ ] something to do",
            "- [x] something done",
            "1. first",
            "7. seventh",
            "just a sentence",
            "",
        ])
    func lineKindsRoundTrip(line: String) {
        #expect(roundTrip(line) == line)
    }

    @Test("A horizontal rule survives as a rule")
    func ruleRoundTrips() {
        #expect(roundTrip("---") == "---")
        // The other spellings are read, and all of them are written one way.
        #expect(roundTrip("***") == "---")
        #expect(roundTrip("___") == "---")
    }

    @Test("Nesting is two spaces a level, both ways")
    func nestingRoundTrips() {
        let markdown = """
            - top
              - one in
                - two in
            """
        #expect(roundTrip(markdown) == markdown)
    }

    @Test("A tab indents the same as two spaces")
    func tabsAreAnIndent() {
        #expect(roundTrip("- top\n\t- one in") == "- top\n  - one in")
    }

    @Test("A whole note round trips")
    func documentRoundTrips() {
        let markdown = """
            # Release checklist

            1. run the tests
            2. check the warnings
              1. formatting clean
            ---
            - [x] signed
            - [ ] notarised

            See [the docs](https://example.com/guide) before starting.
            """
        #expect(roundTrip(markdown) == markdown)
    }

    // MARK: - Inline

    @Test(
        "Emphasis survives the round trip",
        arguments: [
            "**bold**",
            "*italic*",
            "~~struck~~",
            "`code`",
            "a **bold** word",
            "**bold** and *italic* and ~~struck~~",
            "[a link](https://example.com)",
            "text with `inline code` in it",
        ])
    func emphasisRoundTrips(line: String) {
        #expect(roundTrip(line) == line)
    }

    @Test("Underscores are read as emphasis and written as asterisks")
    func underscoreEmphasis() {
        #expect(roundTrip("__bold__") == "**bold**")
        #expect(roundTrip("_italic_") == "*italic*")
    }

    /// `** bold **` is not bold in any renderer — the markers have to touch
    /// the text. A run that carries its own padding has to put the spaces
    /// outside the markers on the way out.
    @Test("Emphasis markers never end up with space inside them")
    func emphasisKeepsSpacesOutside() {
        let attributed = NSMutableAttributedString(
            string: "a bold word",
            attributes: [.font: base, .foregroundColor: NSColor.white])
        let bold = NSFont(
            descriptor: base.fontDescriptor.withSymbolicTraits(base.fontDescriptor.symbolicTraits.union(.bold)),
            size: base.pointSize)!
        // The emphasised run includes the spaces on both sides of "bold".
        attributed.addAttribute(.font, value: bold, range: NSRange(location: 1, length: 6))

        let markdown = NoteMarkdown.markdown(from: attributed, baseFont: base)

        #expect(markdown == "a **bold** word")

        // Read it back: the emphasised run must be the word alone, with the
        // spaces outside it, or no renderer will show it as bold.
        let reread = NoteMarkdown.attributed(fromMarkdown: markdown, baseFont: base, textColor: .white)
        var emphasised: [String] = []
        reread.enumerateAttribute(.font, in: NSRange(location: 0, length: reread.length)) { value, range, _ in
            guard let font = value as? NSFont, font.fontDescriptor.symbolicTraits.contains(.bold) else { return }
            emphasised.append((reread.string as NSString).substring(with: range))
        }
        #expect(emphasised == ["bold"])
    }

    /// "2 * 3 * 4" is arithmetic. A reader that took the first asterisk as the
    /// start of emphasis would swallow the rest of the line.
    @Test("A marker that never closes is text")
    func unclosedMarkersStayLiteral() {
        #expect(roundTrip("2 \\* 3") == "2 \\* 3")
        let runs = NoteMarkdown.inlineRuns("a * b")
        #expect(runs.count == 1)
        #expect(runs.first?.text == "a * b")
        #expect(runs.first?.style.rawValue == 0)
    }

    @Test("Nothing inside a code span is markup")
    func codeSpansAreLiteral() {
        let runs = NoteMarkdown.inlineRuns("`a *b* c`")
        #expect(runs.count == 1)
        #expect(runs.first?.text == "a *b* c")
        #expect(runs.first?.style.contains(.code) == true)
        #expect(roundTrip("`a *b* c`") == "`a *b* c`")
    }

    @Test("A link keeps the emphasis inside it")
    func emphasisInsideLink() {
        let runs = NoteMarkdown.inlineRuns("[**bold** plain](https://example.com)")
        #expect(runs.count == 2)
        #expect(runs.first?.style.contains(.bold) == true)
        #expect(runs.allSatisfy { $0.link == "https://example.com" })
    }

    // MARK: - Code blocks

    @Test("A run of code lines is fenced")
    func codeBlockRoundTrips() {
        let markdown = """
            ```
            git add -p
            git commit
            ```
            """
        #expect(roundTrip(markdown) == markdown)
    }

    /// One line of code is a span. Writing it as a fence would spend three
    /// lines of markdown saying one short thing.
    @Test("A single code line stays a span")
    func singleCodeLineIsNotFenced() {
        #expect(roundTrip("`git status`") == "`git status`")
    }

    @Test("Nothing inside a fence is markup")
    func fenceContentIsLiteral() {
        let markdown = """
            ```
            - not a bullet
            # not a heading
            **not bold**
            ```
            """
        let attributed = NoteMarkdown.attributed(fromMarkdown: markdown, baseFont: base, textColor: .white)
        #expect(attributed.string == "- not a bullet\n# not a heading\n**not bold**")
        #expect(roundTrip(markdown) == markdown)
    }

    @Test("A fence sits between ordinary lines without swallowing them")
    func fenceAmongProse() {
        let markdown = """
            before

            ```
            one
            two
            ```

            after
            """
        #expect(roundTrip(markdown) == markdown)
    }

    @Test("Code lines are recognised by every character carrying the chip")
    func entirelyCodeIsWhatCounts() {
        let mixed = NoteMarkdown.attributed(fromMarkdown: "text with `code` in it", baseFont: base, textColor: .white)
        let paragraphs = NoteMarkdown.paragraphs(of: mixed, baseFont: base)
        #expect(paragraphs.count == 1)
        #expect(paragraphs[0].isEntirelyCode == false)
    }

    // MARK: - Escaping

    /// A line the editor decided is prose must not come back as a list. This
    /// is the same rule the editor applies while typing, carried across the
    /// export: the note said it, so the markdown has to preserve it.
    @Test(
        "Prose that looks like markup comes back as prose",
        arguments: [
            "- not a bullet",
            "# not a heading",
            "1998. that was the year",
            "* not a bullet either",
            "> not a quote",
        ])
    func proseIsEscaped(line: String) {
        let attributed = NSAttributedString(
            string: line, attributes: [.font: base, .foregroundColor: NSColor.white])
        let markdown = NoteMarkdown.markdown(from: attributed, baseFont: base)

        #expect(markdown != line, "an unescaped line would be read back as markup")
        let back = NoteMarkdown.attributed(fromMarkdown: markdown, baseFont: base, textColor: .white)
        #expect(back.string == line)
    }

    @Test("Characters that mean something inline are escaped")
    func inlineEscaping() {
        let line = "a * b _ c ` d [ e ] f ~ g"
        let attributed = NSAttributedString(
            string: line, attributes: [.font: base, .foregroundColor: NSColor.white])
        let markdown = NoteMarkdown.markdown(from: attributed, baseFont: base)
        let back = NoteMarkdown.attributed(fromMarkdown: markdown, baseFont: base, textColor: .white)
        #expect(back.string == line)
    }

    // MARK: - Recognising it

    /// The cost of a false positive is someone's pasted paragraph being
    /// restyled; the cost of a false negative is markdown arriving as its own
    /// source, which is at least still the words. So this leans toward not
    /// converting.
    @Test(
        "Structure is what makes text markdown",
        arguments: [
            "# a heading",
            "- a bullet",
            "* a bullet",
            "+ a bullet",
            "1. first",
            "---",
            "see [the docs](https://example.com)",
            "  - indented bullet",
        ])
    func structureIsRecognised(text: String) {
        #expect(NoteMarkdown.looksLikeMarkdown(text))
    }

    @Test(
        "Prose is left as prose",
        arguments: [
            "just a sentence",
            "2 * 3 * 4 = 24",
            "a_variable_name in code",
            "he said **something** about it",
            "1998. that was the year",
            "",
            "an unclosed [bracket",
        ])
    func proseIsNotConverted(text: String) {
        #expect(!NoteMarkdown.looksLikeMarkdown(text))
    }

    @Test("A note pasted from somewhere else keeps its shape")
    func pastedNoteKeepsItsShape() {
        let pasted = """
            ## Standup
            - [x] shipped the fix
            - [ ] write it up
            """
        #expect(NoteMarkdown.looksLikeMarkdown(pasted))
        let attributed = NoteMarkdown.attributed(fromMarkdown: pasted, baseFont: base, textColor: .white)
        // The stored form uses the editor's own glyphs, which is what the
        // text view turns into drawn checkboxes when it loads the note.
        #expect(attributed.string.contains(StickyNoteMarkup.checkedGlyph + "\t"))
        #expect(attributed.string.contains(StickyNoteMarkup.uncheckedGlyph + "\t"))
        #expect(NoteMarkdown.markdown(from: attributed, baseFont: base) == pasted)
    }

    // MARK: - Headings

    /// The heading font is bold. Measuring emphasis against the body font
    /// would wrap every heading in asterisks.
    @Test("A heading is not also bold text")
    func headingIsNotEmphasis() {
        let markdown = roundTrip("## Second level")
        #expect(markdown == "## Second level")
        #expect(!markdown.contains("**"))
    }

    @Test("A heading survives the note being rescaled")
    func headingSurvivesRescaling() {
        // Notes store absolute sizes and Cmd+/− rescales everything, so the
        // levels have to be recognised by ratio rather than by point size.
        let attributed = NoteMarkdown.attributed(fromMarkdown: "# Title", baseFont: base, textColor: .white)
        let bigger = NSFont.monospacedSystemFont(ofSize: base.pointSize * 1.5, weight: .regular)
        let scaled = NSMutableAttributedString(attributedString: attributed)
        scaled.enumerateAttribute(.font, in: NSRange(location: 0, length: scaled.length)) { value, range, _ in
            guard let font = value as? NSFont else { return }
            let resized = NSFont(descriptor: font.fontDescriptor, size: font.pointSize * 1.5)!
            scaled.addAttribute(.font, value: resized, range: range)
        }
        #expect(NoteMarkdown.markdown(from: scaled, baseFont: bigger) == "# Title")
    }

    @Test("More hashes than the editor has levels is not a heading")
    func tooManyHashes() {
        let back = NoteMarkdown.attributed(fromMarkdown: "#### deep", baseFont: base, textColor: .white)
        #expect(back.string == "#### deep")
    }
}
