import AppKit

/// Writing the notes out as a folder of markdown files.
///
/// The store already keeps notes as real RTF, so they open in TextEdit and
/// Spotlight finds them. This is the other half: a copy that anything reads,
/// that survives this app being uninstalled, and that syncs if the folder
/// chosen happens to live in iCloud Drive. No format of ours in sight.
enum NoteExport {

    /// The note's body font, worked out from the note.
    ///
    /// Export has to know which size counts as body text, because that is how
    /// a heading is recognised — but the font is the widget's setting, and a
    /// note is no longer owned by a widget. So it is read back out of the
    /// note: whichever size most of the characters are set in is the body,
    /// which is what makes the headings the exceptions.
    static func inferredBaseFont(of attributed: NSAttributedString) -> NSFont {
        guard attributed.length > 0 else { return .systemFont(ofSize: 18) }

        // Counted by line, not by character. Counting characters lets one
        // heading outweigh the prose under it in a short note — and the
        // newline ending a heading carries the heading's own font, so it
        // votes for the heading too. Lines are what a person sees.
        var linesBySize: [CGFloat: Int] = [:]
        var fontBySize: [CGFloat: NSFont] = [:]
        let text = attributed.string as NSString
        var location = 0

        while location < text.length {
            let paragraph = text.lineRange(for: NSRange(location: location, length: 0))
            location = paragraph.location + paragraph.length
            guard let font = attributed.attribute(.font, at: paragraph.location, effectiveRange: nil) as? NSFont
            else { continue }

            linesBySize[font.pointSize, default: 0] += 1
            // Keep the plainest font seen at a size: a heading is bold, and
            // inheriting that would make every line read as emphasised.
            let existing = fontBySize[font.pointSize]
            if existing == nil
                || (existing!.fontDescriptor.symbolicTraits.contains(.bold)
                    && !font.fontDescriptor.symbolicTraits.contains(.bold))
            {
                fontBySize[font.pointSize] = font
            }
        }

        // Ties go to the smaller size. Nothing in the editor makes text
        // smaller than the body — headings are 1.15x and up — so when a note
        // is one heading and one line of prose, the prose is the body.
        let body = linesBySize.max { a, b in
            a.value != b.value ? a.value < b.value : a.key > b.key
        }
        guard let size = body?.key, let font = fontBySize[size] else { return .systemFont(ofSize: 18) }
        return font
    }

    /// A note's markdown, given the RTF the store holds.
    static func markdown(forRTF data: Data) -> String? {
        guard !data.isEmpty, let attributed = NSAttributedString(rtf: data, documentAttributes: nil) else {
            return nil
        }
        return NoteMarkdown.markdown(from: attributed, baseFont: inferredBaseFont(of: attributed))
    }

    // MARK: - Names

    /// A filename for a note, from its title.
    ///
    /// Titles are whatever someone typed on the first line, so two notes can
    /// easily share one, and some notes have nothing usable at all. Names are
    /// therefore made unique against the ones already used rather than assumed
    /// to be — writing the second "Groceries" over the first would lose it.
    static func filename(for title: String, taken: inout Set<String>) -> String {
        let base = slug(title)
        var candidate = base
        var suffix = 2
        while taken.contains(candidate) {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }
        taken.insert(candidate)
        return candidate + ".md"
    }

    /// Letters and digits survive, in any language; everything else becomes a
    /// single hyphen. The result is a filename, so it also has to be one a
    /// person can type and a filesystem will take.
    static func slug(_ title: String) -> String {
        var out = ""
        var pendingSeparator = false
        for character in title.lowercased() {
            if character.isLetter || character.isNumber {
                if pendingSeparator, !out.isEmpty { out.append("-") }
                pendingSeparator = false
                out.append(character)
            } else {
                pendingSeparator = true
            }
        }
        // Trimmed after the fact rather than by stopping early: cutting mid
        // word can leave the separator dangling, and a name ending in a
        // hyphen looks like a mistake.
        var name = String(out.prefix(nameLimit))
        while name.hasSuffix("-") { name.removeLast() }
        return name.isEmpty ? "note" : name
    }

    /// Long enough to stay recognisable, short enough that the name plus its
    /// extension is comfortable in any filesystem and any listing.
    static let nameLimit = 50

    // MARK: - Writing

    struct Result: Equatable {
        var written: Int
        var skipped: Int
    }

    /// Writes every note in the store into `directory` as markdown.
    ///
    /// An empty note is skipped rather than written as an empty file: a folder
    /// of notes should be the notes, not a record of every widget ever placed.
    @discardableResult
    static func write(store: NoteStore, to directory: URL) -> Result {
        var taken: Set<String> = []
        var result = Result(written: 0, skipped: 0)

        AppLog.attempt("creating the notes export folder") {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        for record in store.records().sorted(by: { $0.created < $1.created }) {
            guard let data = Data(base64Encoded: store.body(id: record.id)),
                let markdown = markdown(forRTF: data),
                !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                result.skipped += 1
                continue
            }

            let url = directory.appendingPathComponent(filename(for: record.title, taken: &taken))
            let wrote = AppLog.attempt("writing \(url.lastPathComponent)") {
                try Data(markdown.utf8).write(to: url, options: .atomic)
            }
            if wrote { result.written += 1 } else { result.skipped += 1 }
        }

        return result
    }
}
