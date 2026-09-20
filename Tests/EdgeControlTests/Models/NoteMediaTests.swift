import AppKit
import Foundation
import Testing

@testable import EdgeControl

/// RTF carries no images, so a note points at one sitting beside it. The
/// pointer is a link, and a link is text in a file that can be edited by hand
/// or imported from someone else's layout — so what it names is checked, not
/// trusted.
@Suite("Note media")
struct NoteMediaTests {

    // MARK: - What the bytes are

    private func header(_ bytes: [UInt8], padTo count: Int = 24) -> Data {
        var data = Data(bytes)
        while data.count < count { data.append(0) }
        return data
    }

    @Test(
        "An image is identified by its bytes, not by what it was called",
        arguments: [
            ([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], "png"),
            ([0xFF, 0xD8, 0xFF, 0xE0], "jpg"),
            ([0x47, 0x49, 0x46, 0x38, 0x39, 0x61], "gif"),
            ([0x49, 0x49, 0x2A, 0x00], "tiff"),
            ([0x4D, 0x4D, 0x00, 0x2A], "tiff"),
            ([0x42, 0x4D, 0x00, 0x00], "bmp"),
        ])
    func recognisedFormats(bytes: [UInt8], expected: String) {
        #expect(NoteMedia.fileExtension(for: header(bytes)) == expected)
    }

    @Test("ISO base media brands are read past the length field")
    func heicAndAvif() {
        let heic = header([0, 0, 0, 0x18] + Array("ftypheic".utf8))
        let avif = header([0, 0, 0, 0x18] + Array("ftypavif".utf8))
        #expect(NoteMedia.fileExtension(for: heic) == "heic")
        #expect(NoteMedia.fileExtension(for: avif) == "avif")
    }

    /// Writing unknown bytes into the notes folder under a guessed extension
    /// produces a file nothing can open. Refusing is the better answer.
    @Test("Anything unrecognised is refused")
    func unknownFormats() {
        #expect(NoteMedia.fileExtension(for: Data()) == nil)
        #expect(NoteMedia.fileExtension(for: Data("just text".utf8)) == nil)
        #expect(NoteMedia.fileExtension(for: header([0x25, 0x50, 0x44, 0x46])) == nil)  // PDF
        #expect(NoteMedia.fileExtension(for: header([0, 0, 0, 0x18] + Array("ftypmp42".utf8))) == nil)
        // Too short to carry a signature at all.
        #expect(NoteMedia.fileExtension(for: Data([0x89, 0x50])) == nil)
    }

    @Test("A name is only made for data that is an image")
    func filenames() {
        let png = header([0x89, 0x50, 0x4E, 0x47])
        #expect(NoteMedia.filename(for: png, ordinal: 1, suffix: "abc") == "image-1-abc.png")
        #expect(NoteMedia.filename(for: Data("text".utf8), ordinal: 1, suffix: "abc") == nil)
    }

    // MARK: - The link

    @Test("A media link round trips through its file name")
    func linkRoundTrip() {
        let link = NoteMedia.link(forFile: "image-1-abc.png")
        #expect(NoteMedia.file(fromLink: link) == "image-1-abc.png")
    }

    @Test("An ordinary link is not a media link")
    func ordinaryLinks() {
        #expect(NoteMedia.file(fromLink: "https://example.com/cat.png") == nil)
        #expect(NoteMedia.file(fromLink: "image-1.png") == nil)
        #expect(NoteMedia.file(fromLink: "") == nil)
    }

    /// The name in a link decides which file is opened, so a link carrying a
    /// path would reach outside the note's own folder.
    @Test(
        "A link that names anything but a plain file is refused",
        arguments: [
            "edgecontrol-media:../../../etc/passwd",
            "edgecontrol-media:/etc/passwd",
            "edgecontrol-media:sub/dir/image.png",
            "edgecontrol-media:..",
            "edgecontrol-media:.",
            "edgecontrol-media:.hidden",
            "edgecontrol-media:",
        ])
    func traversalIsRefused(link: String) {
        #expect(NoteMedia.file(fromLink: link) == nil)
    }

    @Test("A very long name is refused")
    func absurdNames() {
        let long = String(repeating: "a", count: 200) + ".png"
        #expect(!NoteMedia.isSafeFilename(long))
        #expect(NoteMedia.file(fromLink: NoteMedia.link(forFile: long)) == nil)
    }

    // MARK: - Markdown

    private let base = NSFont.monospacedSystemFont(ofSize: 18, weight: .regular)

    @Test("An image round trips through markdown")
    func imageRoundTrips() {
        let markdown = "![image-1-abc.png](image-1-abc.png)"
        let attributed = NoteMarkdown.attributed(fromMarkdown: markdown, baseFont: base, textColor: .white)
        let link = attributed.attribute(.link, at: 0, effectiveRange: nil)
        #expect(NoteMedia.file(fromLink: link as? String ?? "") == "image-1-abc.png")
        #expect(NoteMarkdown.markdown(from: attributed, baseFont: base) == markdown)
    }

    @Test("An exported image path points at the folder beside the note")
    func exportedPath() {
        let attributed = NoteMarkdown.attributed(
            fromMarkdown: "![shot.png](shot.png)", baseFont: base, textColor: .white)
        let markdown = NoteMarkdown.markdown(
            from: attributed, baseFont: base, mediaPath: { "media/groceries/\($0)" })
        #expect(markdown == "![shot.png](media/groceries/shot.png)")
    }

    /// There is no file beside the note to draw, and inventing one would be
    /// worse than saying plainly what it is.
    @Test("An image somewhere else on the web is read as a link")
    func remoteImagesBecomeLinks() {
        let attributed = NoteMarkdown.attributed(
            fromMarkdown: "![a cat](https://example.com/cat.png)", baseFont: base, textColor: .white)
        #expect(attributed.string == "a cat")
        let link = attributed.attribute(.link, at: 0, effectiveRange: nil) as? String
        #expect(link == "https://example.com/cat.png")
        #expect(NoteMedia.file(fromLink: link ?? "") == nil)
    }

    @Test("A path that tries to climb out is not treated as the note's own")
    func traversalInMarkdown() {
        #expect(NoteMarkdownParserProbe.mediaFilename(in: "../../secret.png") == "secret.png")
        #expect(NoteMarkdownParserProbe.mediaFilename(in: "https://example.com/cat.png") == nil)
        #expect(NoteMarkdownParserProbe.mediaFilename(in: "data:image/png;base64,AAAA") == nil)
        // A name with no extension is prose in brackets, not a file.
        #expect(NoteMarkdownParserProbe.mediaFilename(in: "nothing") == nil)
    }

    // MARK: - The store

    @Test("An image is written beside its note and read back")
    func storeRoundTrip() {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NoteMediaTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NoteStore(directory: directory)

        let png = header([0x89, 0x50, 0x4E, 0x47])
        let name = store.writeMedia(png, for: "note-1")
        #expect(name?.hasSuffix(".png") == true)
        #expect(store.mediaData(named: name ?? "", for: "note-1") == png)
        #expect(store.mediaNames(for: "note-1") == [name])

        // Refused rather than written under a guessed name.
        #expect(store.writeMedia(Data("text".utf8), for: "note-1") == nil)

        // Deleting the note takes its images with it.
        store.delete(id: "note-1")
        #expect(store.mediaNames(for: "note-1").isEmpty)
    }

    @Test("A store read cannot be talked into leaving the note's folder")
    func storeRefusesTraversal() {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NoteMediaTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NoteStore(directory: directory)

        #expect(store.mediaData(named: "../../../etc/passwd", for: "note-1") == nil)
        #expect(store.mediaData(named: "/etc/passwd", for: "note-1") == nil)
    }

    // MARK: - Drawing

    @Test("A pasted screenshot is scaled to fit, and a small image is left alone")
    func attachmentSizing() {
        let big = MediaAttachment.fittedSize(of: NSSize(width: 2560, height: 1440))
        #expect(big.width <= MediaAttachment.maximumSize.width)
        #expect(big.height <= MediaAttachment.maximumSize.height)
        // Proportions kept.
        #expect(abs(big.width / big.height - 2560.0 / 1440.0) < 0.05)

        let small = MediaAttachment.fittedSize(of: NSSize(width: 16, height: 16))
        #expect(small == NSSize(width: 16, height: 16))
    }
}

/// `mediaFilename` is internal to the parser's own file; this reaches it
/// without widening its visibility for the app.
enum NoteMarkdownParserProbe {
    static func mediaFilename(in path: String) -> String? {
        NoteMarkdown.mediaFilename(in: path)
    }
}
