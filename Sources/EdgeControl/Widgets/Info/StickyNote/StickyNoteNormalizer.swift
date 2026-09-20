import AppKit

/// Everything a note needs doing to it after it is loaded, pasted into, or
/// typed in.
///
/// The passes run on every change and on every load, which makes them the
/// code most likely to be wrong and, until now, the code least possible to
/// check: they lived on the text view, and reaching them needed an
/// NSTextStorage inside a window. Here they take a mutable attributed string
/// and nothing else, so a test can hand one over and read the result.
///
/// Order matters and is the whole design:
///
/// 1. Checkbox glyphs become drawn boxes. Storage keeps characters so the
///    file means something to anything else that opens it; the view draws.
/// 2. Media links become drawn images, for the same reason.
/// 3. Paragraph geometry is restamped, which is also where a pre-tab note
///    picks up the aligned list column.
/// 4. Ordered lists are renumbered.
/// 5. Tracking is stamped over the lot.
///
/// Drawing first because the later passes measure lines, and a line with a
/// glyph in it measures differently from one with an attachment.
struct StickyNoteNormalizer {
    let layout: StickyNoteLayout
    let defaultFont: NSFont
    let defaultColor: NSColor
    let accentColor: NSColor
    /// Supplies an image's bytes by filename. Absent means "do not draw
    /// images", which is what a note being converted outside an editor wants.
    var readMedia: ((String) -> Data?)?

    func normalize(_ storage: NSMutableAttributedString) {
        drawCheckboxes(in: storage)
        drawMedia(in: storage)
        applyParagraphSpacing(to: storage)
        renumberOrderedLists(in: storage)
        applyTracking(to: storage)
    }

    // MARK: - Drawing

    /// Storage carries ☐/☑ characters; the view draws them. Any glyph that
    /// appears — from a load, a paste, or a note written before the boxes
    /// were drawn — becomes an attachment.
    ///
    /// Backwards, because each replacement changes the length of everything
    /// after it.
    func drawCheckboxes(in storage: NSMutableAttributedString) {
        var index = storage.length - 1
        let text = storage.string as NSString
        while index >= 0 {
            let character = text.substring(with: NSRange(location: index, length: 1))
            if character == StickyNoteMarkup.uncheckedGlyph || character == StickyNoteMarkup.checkedGlyph {
                storage.replaceCharacters(
                    in: NSRange(location: index, length: 1),
                    with: checkbox(checked: character == StickyNoteMarkup.checkedGlyph))
            }
            index -= 1
        }
    }

    /// Turns the media links a loaded note carries into drawn images.
    func drawMedia(in storage: NSMutableAttributedString) {
        guard let readMedia else { return }
        var location = storage.length
        while location > 0 {
            var effective = NSRange()
            let probe = max(0, location - 1)
            let link = storage.attribute(.link, at: probe, effectiveRange: &effective)
            location = effective.location

            guard storage.attribute(.attachment, at: probe, effectiveRange: nil) == nil,
                let name = NoteMedia.file(fromLink: Self.linkString(link)),
                let data = readMedia(name),
                let attachment = MediaAttachment.make(filename: name, data: data)
            else { continue }

            let drawn = NSMutableAttributedString(attachment: attachment)
            drawn.addAttributes(
                [.font: defaultFont, .link: NoteMedia.link(forFile: name)],
                range: NSRange(location: 0, length: drawn.length))
            storage.replaceCharacters(in: effective, with: drawn)
        }
    }

    /// A drawn box on its own, with no marker geometry around it.
    func checkbox(checked: Bool) -> NSAttributedString {
        let attachment = CheckboxAttachment.make(
            checked: checked, font: defaultFont, stroke: defaultColor, accent: accentColor)
        let drawn = NSMutableAttributedString(attachment: attachment)
        drawn.addAttributes(
            [.cursor: NSCursor.pointingHand, .font: defaultFont],
            range: NSRange(location: 0, length: drawn.length))
        return drawn
    }

    static func linkString(_ value: Any?) -> String {
        if let url = value as? URL { return url.absoluteString }
        if let string = value as? String { return string }
        return ""
    }

    // MARK: - Geometry

    /// Every paragraph gets its rhythm: heading-sized first characters get
    /// the heading spacing, everything else the body spacing.
    func applyParagraphSpacing(to storage: NSMutableAttributedString) {
        guard storage.length > 0 else { return }
        let headingThreshold = defaultFont.pointSize * 1.1
        var location = 0

        while location < (storage.string as NSString).length {
            let text = storage.string as NSString
            let paragraph = text.lineRange(for: NSRange(location: location, length: 0))
            var line = text.substring(with: paragraph)
            if line.hasSuffix("\n") { line.removeLast() }

            // A note written before the tab separator existed picks up the
            // aligned list column here; the same paragraph is then re-read.
            if line.count >= 2, StickyNoteMarkup.marker(of: line) != nil, !line.contains("\t") {
                storage.replaceCharacters(
                    in: NSRange(location: paragraph.location + 1, length: 1), with: "\t")
                continue
            }

            let isList = StickyNoteMarkup.markerLength(of: line) > 0
            let firstFont = storage.attribute(.font, at: paragraph.location, effectiveRange: nil) as? NSFont
            let existing =
                storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle
            let style = layout.paragraphStyle(
                isHeading: !isList && (firstFont?.pointSize ?? 0) > headingThreshold,
                isList: isList,
                markerInset: layout.markerInset(for: line),
                level: layout.indentLevel(of: existing, isList: isList))
            storage.addAttribute(.paragraphStyle, value: style, range: paragraph)
            location = paragraph.location + paragraph.length
        }
    }

    /// Numbered items in a contiguous block stay sequential per indent level:
    /// each follows the previous number at its level, bullets and checkboxes
    /// between them do not break the count, and any non-list line — blank or
    /// prose — ends the block and resets it. The block's first number is kept
    /// as typed, so a list may start anywhere.
    func renumberOrderedLists(in storage: NSMutableAttributedString) {
        guard storage.length > 0 else { return }
        var counters: [Int: Int] = [:]
        var location = 0

        while location < (storage.string as NSString).length {
            let text = storage.string as NSString
            let paragraph = text.lineRange(for: NSRange(location: location, length: 0))
            var line = text.substring(with: paragraph)
            if line.hasSuffix("\n") { line.removeLast() }

            if StickyNoteMarkup.markerLength(of: line) == 0 {
                counters.removeAll()
                location = paragraph.location + paragraph.length
                continue
            }

            if let tab = line.firstIndex(of: "\t"), line[..<tab].hasSuffix("."),
                let number = Int(line[..<tab].dropLast())
            {
                let existing =
                    storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil)
                    as? NSParagraphStyle
                let level = layout.indentLevel(of: existing, isList: true)
                counters = counters.filter { $0.key <= level }
                let expected = counters[level].map { $0 + 1 } ?? number
                counters[level] = expected

                if number != expected {
                    let headLength = (String(line[..<tab]) as NSString).length
                    storage.replaceCharacters(
                        in: NSRange(location: paragraph.location, length: headLength),
                        with: "\(expected).")
                    let fresh = (storage.string as NSString)
                        .lineRange(for: NSRange(location: paragraph.location, length: 0))
                    location = fresh.location + fresh.length
                    continue
                }
            }
            location = paragraph.location + paragraph.length
        }
    }

    /// Stamps the family's tracking over everything, so loaded and pasted
    /// text is covered, and clears it when the family does not need it.
    func applyTracking(to storage: NSMutableAttributedString) {
        guard storage.length > 0 else { return }
        let all = NSRange(location: 0, length: storage.length)
        if layout.kern > 0 {
            storage.addAttribute(.kern, value: layout.kern, range: all)
        } else {
            storage.removeAttribute(.kern, range: all)
        }
    }
}
