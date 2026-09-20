import AppKit
import Foundation
import Testing

@testable import EdgeControl

@Suite("Note export")
struct NoteExportTests {

    private let base = NSFont.monospacedSystemFont(ofSize: 18, weight: .regular)

    private func withStore(_ body: (NoteStore, URL) throws -> Void) rethrows {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NoteExportTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(NoteStore(directory: directory.appendingPathComponent("store")), directory)
    }

    private func rtf(_ markdown: String, font: NSFont? = nil) -> String {
        let attributed = NoteMarkdown.attributed(
            fromMarkdown: markdown, baseFont: font ?? base, textColor: .white)
        let data = attributed.rtf(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])!
        return data.base64EncodedString()
    }

    // MARK: - Names

    @Test(
        "A title becomes a filename",
        arguments: [
            ("Release checklist", "release-checklist"),
            ("Groceries", "groceries"),
            ("  spaced  out  ", "spaced-out"),
            ("Symbols!!! @#$ here", "symbols-here"),
            ("", "note"),
            ("!!!", "note"),
        ])
    func titlesBecomeNames(title: String, expected: String) {
        var taken: Set<String> = []
        #expect(NoteExport.filename(for: title, taken: &taken) == expected + ".md")
    }

    @Test("Letters that are not ASCII are still letters")
    func nonASCIITitles() {
        var taken: Set<String> = []
        // A filename in the language the note was written in beats one made of
        // hyphens. APFS takes it, and so does every renderer.
        #expect(NoteExport.filename(for: "Alışveriş", taken: &taken) == "alışveriş.md")
        #expect(NoteExport.slug("日本語のノート") == "日本語のノート")
    }

    /// Two notes sharing a title is ordinary — a title is just the first line.
    /// Writing the second over the first would lose it.
    @Test("Notes that share a title get separate files")
    func namesAreMadeUnique() {
        var taken: Set<String> = []
        #expect(NoteExport.filename(for: "Groceries", taken: &taken) == "groceries.md")
        #expect(NoteExport.filename(for: "Groceries", taken: &taken) == "groceries-2.md")
        #expect(NoteExport.filename(for: "groceries", taken: &taken) == "groceries-3.md")
    }

    @Test("A very long first line does not become a very long filename")
    func longTitles() {
        var taken: Set<String> = []
        let name = NoteExport.filename(for: String(repeating: "word ", count: 40), taken: &taken)
        #expect(name.count <= 53)
        #expect(name.hasSuffix(".md"))
    }

    // MARK: - Body font

    /// The font is the widget's setting and a note no longer belongs to a
    /// widget, so export reads the body size back out of the note itself.
    /// Getting this wrong turns every line into a heading, or none of them.
    @Test("The body font is the size most of the note is written in")
    func bodyFontIsInferred() {
        let note = NoteMarkdown.attributed(
            fromMarkdown: "# Title\n\nbody one\nbody two\nbody three",
            baseFont: base, textColor: .white)
        #expect(NoteExport.inferredBaseFont(of: note).pointSize == base.pointSize)
    }

    @Test("The inferred font is not the bold one a heading uses")
    func inferredFontIsNotBold() {
        let note = NoteMarkdown.attributed(fromMarkdown: "# Title\nbody", baseFont: base, textColor: .white)
        let inferred = NoteExport.inferredBaseFont(of: note)
        #expect(!inferred.fontDescriptor.symbolicTraits.contains(.bold))
    }

    @Test("An empty note still yields a usable font")
    func emptyNoteFont() {
        #expect(NoteExport.inferredBaseFont(of: NSAttributedString()).pointSize > 0)
    }

    @Test("Headings survive the round trip through the store")
    func headingsSurviveExport() {
        let markdown = "# Title\n\n- [x] done\n- [ ] not done\n\nSee [docs](https://example.com)."
        let attributed = NoteMarkdown.attributed(fromMarkdown: markdown, baseFont: base, textColor: .white)
        let data = attributed.rtf(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])!
        #expect(NoteExport.markdown(forRTF: data) == markdown)
    }

    // MARK: - Writing

    @Test("Every note becomes a file")
    func writesAFilePerNote() throws {
        try withStore { store, directory in
            store.save(
                id: "a", rtfBase64: rtf("# Groceries\n- [ ] milk"), plainText: "Groceries\nmilk",
                now: Date(timeIntervalSince1970: 1_000))
            store.save(
                id: "b", rtfBase64: rtf("# Standup\n- shipped it"), plainText: "Standup\nshipped it",
                now: Date(timeIntervalSince1970: 2_000))

            let out = directory.appendingPathComponent("export")
            let result = NoteExport.write(store: store, to: out)

            #expect(result == NoteExport.Result(written: 2, skipped: 0))
            let names = try FileManager.default.contentsOfDirectory(atPath: out.path).sorted()
            #expect(names == ["groceries.md", "standup.md"])

            let groceries = try String(contentsOf: out.appendingPathComponent("groceries.md"), encoding: .utf8)
            #expect(groceries == "# Groceries\n- [ ] milk")
        }
    }

    /// A folder of notes should be the notes. A widget someone placed and
    /// never typed into is not one.
    @Test("An empty note is not written out")
    func emptyNotesAreSkipped() throws {
        try withStore { store, directory in
            store.save(id: "empty", rtfBase64: "", plainText: "", now: Date())
            store.save(id: "real", rtfBase64: rtf("something"), plainText: "something", now: Date())

            let out = directory.appendingPathComponent("export")
            let result = NoteExport.write(store: store, to: out)

            #expect(result == NoteExport.Result(written: 1, skipped: 1))
            let names = try FileManager.default.contentsOfDirectory(atPath: out.path)
            #expect(names == ["something.md"])
        }
    }

    @Test("Exporting twice does not lose a note to a name collision")
    func collisionsAcrossNotes() throws {
        try withStore { store, directory in
            store.save(
                id: "a", rtfBase64: rtf("Groceries\nmilk"), plainText: "Groceries\nmilk",
                now: Date(timeIntervalSince1970: 1_000))
            store.save(
                id: "b", rtfBase64: rtf("Groceries\nbread"), plainText: "Groceries\nbread",
                now: Date(timeIntervalSince1970: 2_000))

            let out = directory.appendingPathComponent("export")
            #expect(NoteExport.write(store: store, to: out) == NoteExport.Result(written: 2, skipped: 0))

            let names = try FileManager.default.contentsOfDirectory(atPath: out.path).sorted()
            #expect(names == ["groceries-2.md", "groceries.md"])
        }
    }

    @Test("Exporting into a folder that does not exist yet creates it")
    func createsTheFolder() {
        withStore { store, directory in
            store.save(id: "a", rtfBase64: rtf("note"), plainText: "note", now: Date())
            let out = directory.appendingPathComponent("does/not/exist")
            #expect(NoteExport.write(store: store, to: out).written == 1)
            #expect(FileManager.default.fileExists(atPath: out.path))
        }
    }

    @Test("An empty store writes nothing and does not fail")
    func emptyStore() {
        withStore { store, directory in
            let out = directory.appendingPathComponent("export")
            #expect(NoteExport.write(store: store, to: out) == NoteExport.Result(written: 0, skipped: 0))
        }
    }
}
