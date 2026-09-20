import AppKit
import SwiftUI

// The editor itself: paragraph styling, list markers, typing conversions,
// checkbox toggling and link pasting.

final class LinkPasteTextView: NSTextView {
    var defaultFont: NSFont = .systemFont(ofSize: 18)
    var defaultColor: NSColor = .white
    var accentColor: NSColor = .systemYellow
    var onFontSizeDelta: ((Double) -> Void)?
    var onFontSizeReset: (() -> Void)?
    var writeMedia: ((Data) -> String?)?
    var readMedia: ((String) -> Data?)?
    private var isNormalizing = false
    private lazy var formatBar = StickyNoteFormatBar(owner: self)

    @objc func increaseFontSize(_ sender: Any?) { onFontSizeDelta?(1) }
    @objc func decreaseFontSize(_ sender: Any?) { onFontSizeDelta?(-1) }
    @objc func resetFontSize(_ sender: Any?) { onFontSizeReset?() }

    /// Checkbox images are sized against the body font; redraw them when it
    /// changes so boxes and text scale together.
    func refreshCheckboxImages() {
        guard let storage = textStorage else { return }
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let box = value as? CheckboxAttachment else { return }
            let fresh = CheckboxAttachment.make(
                checked: box.checked, font: defaultFont,
                stroke: defaultColor, accent: accentColor
            )
            storage.addAttribute(.attachment, value: fresh, range: range)
        }
    }

    /// All line geometry lives in StickyNoteLayout, which needs only the font.
    private var layout: StickyNoteLayout { StickyNoteLayout(font: defaultFont) }
    private var noteKern: CGFloat { layout.kern }
    private var listTextIndent: CGFloat { layout.listTextIndent }
    private var indentStep: CGFloat { layout.indentStep }
    private var maxIndentLevel: Int { layout.maxIndentLevel }

    private func markerInset(for line: String) -> CGFloat { layout.markerInset(for: line) }

    private func paragraphStyle(isHeading: Bool, isList: Bool, markerInset: CGFloat, level: Int) -> NSParagraphStyle {
        layout.paragraphStyle(isHeading: isHeading, isList: isList, markerInset: markerInset, level: level)
    }

    private func indentLevel(of style: NSParagraphStyle?, isList: Bool) -> Int {
        layout.indentLevel(of: style, isList: isList)
    }

    private func headingFont(_ level: Int) -> NSFont { layout.headingFont(level) }

    private var bodyAttributes: [NSAttributedString.Key: Any] {
        [
            .font: defaultFont, .foregroundColor: defaultColor,
            .paragraphStyle: bodyParagraph, .kern: noteKern,
        ]
    }

    /// Shared rhythm for body, bullet and checkbox lines.
    private var bodyParagraph: NSParagraphStyle {
        paragraphStyle(isHeading: false, isList: false, markerInset: 0, level: 0)
    }

    private var listParagraph: NSParagraphStyle {
        paragraphStyle(isHeading: false, isList: true, markerInset: 0, level: 0)
    }

    /// Headings breathe a little more, especially above.
    private var headingParagraph: NSParagraphStyle {
        paragraphStyle(isHeading: true, isList: false, markerInset: 0, level: 0)
    }

    /// Leading marker of a line — "•", a drawn checkbox, or "N." — with its
    /// trailing tab. 0 when the line is not a list item.
    private func markerLength(of line: String) -> Int {
        StickyNoteMarkup.markerLength(of: line)
    }

    private var listAttributes: [NSAttributedString.Key: Any] {
        listAttributes(level: 0)
    }

    private func listAttributes(level: Int) -> [NSAttributedString.Key: Any] {
        var a = bodyAttributes
        a[.paragraphStyle] = paragraphStyle(isHeading: false, isList: true, markerInset: 0, level: level)
        return a
    }

    override func didChangeText() {
        // Normalize BEFORE notifying: renumbering can rewrite characters,
        // and observers (the SwiftUI binding) must capture the final text.
        // A stale capture makes the next render reload the view from old
        // RTF, throwing the caret to the end of the note.
        if !isNormalizing {
            isNormalizing = true
            normalizeCheckboxes()
            isNormalizing = false
            // Deleting everything must also clear the invisible pen: with no
            // neighbor to inherit from, stale heading attributes would make
            // an emptied note type headings forever.
            if textStorage?.length == 0 {
                typingAttributes = bodyAttributes
            }
        }
        super.didChangeText()
    }

    /// Format > Body Text: strips heading size, bold/italic, underline and
    /// strikethrough from the selection (or the current line), keeping links.
    @objc func resetToBodyText(_ sender: Any?) {
        guard let storage = textStorage else { return }
        let ns = string as NSString
        var range = selectedRange()
        if range.length == 0 {
            range = ns.lineRange(for: NSRange(location: range.location, length: 0))
        }
        guard range.length > 0 else {
            typingAttributes = bodyAttributes
            return
        }
        guard shouldChangeText(in: range, replacementString: nil) else { return }
        storage.addAttribute(.font, value: defaultFont, range: range)
        storage.addAttribute(.paragraphStyle, value: bodyParagraph, range: range)
        storage.removeAttribute(.strikethroughStyle, range: range)
        storage.removeAttribute(.underlineStyle, range: range)
        didChangeText()
        typingAttributes = bodyAttributes
    }

    /// One drawn checkbox (attachment) plus its following tab.
    private func checkboxMarker(checked: Bool, level: Int = 0) -> NSAttributedString {
        let s = NSMutableAttributedString(attributedString: checkboxOnly(checked: checked))
        s.append(NSAttributedString(string: "\t", attributes: listAttributes(level: level)))
        s.addAttribute(
            .paragraphStyle,
            value: paragraphStyle(isHeading: false, isList: true, markerInset: 0, level: level),
            range: NSRange(location: 0, length: s.length))
        return s
    }

    /// The flipped replacement for an existing box, carrying over the
    /// character's current paragraph style — a bare checkboxOnly() has
    /// none, and normalization would read that as indent level 0,
    /// outdenting the line on every toggle.
    private func toggledBox(_ box: CheckboxAttachment, at location: Int) -> NSAttributedString {
        let s = NSMutableAttributedString(attributedString: checkboxOnly(checked: !box.checked))
        if let style = textStorage?.attribute(.paragraphStyle, at: location, effectiveRange: nil) {
            s.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: s.length))
        }
        return s
    }

    private func checkboxOnly(checked: Bool) -> NSAttributedString {
        let attachment = CheckboxAttachment.make(
            checked: checked, font: defaultFont,
            stroke: defaultColor, accent: accentColor
        )
        let s = NSMutableAttributedString(attachment: attachment)
        s.addAttributes(
            [.cursor: NSCursor.pointingHand, .font: defaultFont],
            range: NSRange(location: 0, length: s.length)
        )
        return s
    }

    /// Storage carries ☐/☑ characters; the view draws them. Any glyph that
    /// appears (load, paste, legacy notes) becomes a drawn attachment.
    func normalizeCheckboxes() {
        guard let storage = textStorage else { return }
        var idx = storage.length - 1
        let ns = storage.string as NSString
        while idx >= 0 {
            let ch = ns.substring(with: NSRange(location: idx, length: 1))
            if ch == "☐" || ch == "☑" {
                let range = NSRange(location: idx, length: 1)
                storage.replaceCharacters(in: range, with: checkboxOnly(checked: ch == "☑"))
            }
            idx -= 1
        }
        normalizeMedia()
        applyParagraphSpacing()
        renumberOrderedLists()
        applyTracking()
    }

    /// Turns the media links a loaded note carries into drawn images.
    ///
    /// Runs backwards for the same reason the checkbox pass does: each
    /// replacement changes the length of everything after it.
    func normalizeMedia() {
        guard let storage = textStorage, let readMedia else { return }
        var location = storage.length
        while location > 0 {
            var effective = NSRange()
            let probe = max(0, location - 1)
            let link = storage.attribute(.link, at: probe, effectiveRange: &effective)
            location = effective.location

            guard storage.attribute(.attachment, at: probe, effectiveRange: nil) == nil,
                let name = NoteMedia.file(fromLink: linkString(link)),
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

    private func linkString(_ value: Any?) -> String {
        if let url = value as? URL { return url.absoluteString }
        if let string = value as? String { return string }
        return ""
    }

    /// Stamps the family's tracking over everything so loaded and pasted
    /// text is covered, and clears it when the family doesn't need it.
    private func applyTracking() {
        guard let storage = textStorage, storage.length > 0 else { return }
        let all = NSRange(location: 0, length: storage.length)
        if noteKern > 0 {
            storage.addAttribute(.kern, value: noteKern, range: all)
        } else {
            storage.removeAttribute(.kern, range: all)
        }
    }

    /// Every paragraph gets its rhythm: heading-sized first characters get
    /// the heading spacing, everything else the body spacing. Runs as part
    /// of normalization so loaded and pasted content is covered too.
    private func applyParagraphSpacing() {
        guard let storage = textStorage, storage.length > 0 else { return }
        let headingThreshold = defaultFont.pointSize * 1.1
        var location = 0
        while location < (storage.string as NSString).length {
            let ns = storage.string as NSString
            let paragraph = ns.lineRange(for: NSRange(location: location, length: 0))
            var line = ns.substring(with: paragraph)
            if line.hasSuffix("\n") { line.removeLast() }

            // Migrate legacy no-break-space separators to tabs so old notes
            // pick up the aligned list column; re-run the same paragraph.
            if line.count >= 2, StickyNoteMarkup.marker(of: line) != nil, !line.contains("\t") {
                storage.replaceCharacters(
                    in: NSRange(location: paragraph.location + 1, length: 1), with: "\t"
                )
                continue
            }

            let isList = markerLength(of: line) > 0
            let firstFont = storage.attribute(.font, at: paragraph.location, effectiveRange: nil) as? NSFont
            let existing =
                storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle
            let style = paragraphStyle(
                isHeading: !isList && (firstFont?.pointSize ?? 0) > headingThreshold,
                isList: isList,
                markerInset: markerInset(for: line),
                level: indentLevel(of: existing, isList: isList)
            )
            storage.addAttribute(.paragraphStyle, value: style, range: paragraph)
            location = paragraph.location + paragraph.length
        }
    }

    /// Numbered items in a contiguous list block stay sequential per indent
    /// level: each one follows the previous number at its level (bullets and
    /// checkboxes between them don't break the count), and any non-list
    /// line — blank or plain text — ends the block and resets numbering.
    /// Runs on every change, so inserting, deleting or converting an item
    /// renumbers the rest of its list. The block's first number is kept
    /// as typed, so lists may start anywhere.
    private func renumberOrderedLists() {
        guard let storage = textStorage, storage.length > 0 else { return }
        var counters: [Int: Int] = [:]
        var location = 0
        while location < (storage.string as NSString).length {
            let ns = storage.string as NSString
            let paragraph = ns.lineRange(for: NSRange(location: location, length: 0))
            var line = ns.substring(with: paragraph)
            if line.hasSuffix("\n") { line.removeLast() }
            if markerLength(of: line) == 0 {
                counters.removeAll()
                location = paragraph.location + paragraph.length
                continue
            }
            if let tab = line.firstIndex(of: "\t"), line[..<tab].hasSuffix("."),
                let n = Int(line[..<tab].dropLast())
            {
                let existing =
                    storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle
                let level = indentLevel(of: existing, isList: true)
                counters = counters.filter { $0.key <= level }
                let expected = counters[level].map { $0 + 1 } ?? n
                counters[level] = expected
                if n != expected {
                    let headLength = (String(line[..<tab]) as NSString).length
                    storage.replaceCharacters(
                        in: NSRange(location: paragraph.location, length: headLength),
                        with: "\(expected)."
                    )
                    let fresh = (storage.string as NSString)
                        .lineRange(for: NSRange(location: paragraph.location, length: 0))
                    location = fresh.location + fresh.length
                    continue
                }
            }
            location = paragraph.location + paragraph.length
        }
    }

    // MARK: Typing conversions

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let str =
            (insertString as? String)
            ?? (insertString as? NSAttributedString)?.string ?? ""

        if str == " ", convertLinePrefix() { return }

        if str == "\n" {
            // Enter with the cursor inside a link opens it instead of
            // breaking the line. Strictly inside: at the link's trailing
            // edge, return still makes a newline so writing can continue.
            if openLinkAtCursorInstead() { return }
            // Enter on an empty bullet/checkbox line ends the list: the
            // marker disappears instead of a new one being created.
            if removeBareListMarker() { return }
            if convertHorizontalRule() { return }
            if let staysInBlock = codeBlockContinuation() {
                super.insertText(insertString, replacementRange: replacementRange)
                typingAttributes = staysInBlock ? codeTypingAttributes : bodyAttributes
                return
            }
            let continuation = listContinuation()
            super.insertText(insertString, replacementRange: replacementRange)
            // A heading ends at the line break; typing resumes as body text.
            typingAttributes = bodyAttributes
            if let continuation {
                super.insertText(continuation, replacementRange: selectedRange())
            }
            return
        }

        // The fence is checked first: on "``" the third backtick would
        // otherwise close a span around the second one.
        if str == "`", convertCodeFence() { return }
        if str == "`", convertCodeSpan() { return }
        if str == "/", showCommandMenu() { return }

        // The bullet waits for the first character after "- ": converting on
        // the space itself created a confusing interstitial state and stole
        // the "[" that starts a checkbox.
        if str.count == 1, str != "[" {
            if (str == "-" || str == "*"), convertCheckboxToBullet() { return }
            convertDashIfPending()
        }
        super.insertText(insertString, replacementRange: replacementRange)
    }

    /// Tab and Shift-Tab indent and unindent the line the caret is on (or
    /// every line the selection touches), wherever the caret sits in it.
    override func insertTab(_ sender: Any?) { changeIndent(by: 1) }
    override func insertBacktab(_ sender: Any?) { changeIndent(by: -1) }

    private func changeIndent(by delta: Int) {
        guard let storage = textStorage else { return }
        let ns = storage.string as NSString
        let lines = ns.lineRange(for: selectedRange())
        // The empty last line has no characters to restyle; move the pen.
        guard lines.length > 0 else {
            let existing = typingAttributes[.paragraphStyle] as? NSParagraphStyle
            let level = max(0, min(maxIndentLevel, indentLevel(of: existing, isList: false) + delta))
            typingAttributes[.paragraphStyle] = paragraphStyle(
                isHeading: false, isList: false, markerInset: 0, level: level)
            return
        }
        guard shouldChangeText(in: lines, replacementString: nil) else { return }
        var location = lines.location
        while location < NSMaxRange(lines) {
            let paragraph = ns.lineRange(for: NSRange(location: location, length: 0))
            var line = ns.substring(with: paragraph)
            if line.hasSuffix("\n") { line.removeLast() }
            let isList = markerLength(of: line) > 0
            let firstFont = storage.attribute(.font, at: paragraph.location, effectiveRange: nil) as? NSFont
            let existing =
                storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle
            let level = max(0, min(maxIndentLevel, indentLevel(of: existing, isList: isList) + delta))
            storage.addAttribute(
                .paragraphStyle,
                value: paragraphStyle(
                    isHeading: !isList && (firstFont?.pointSize ?? 0) > defaultFont.pointSize * 1.1,
                    isList: isList,
                    markerInset: markerInset(for: line),
                    level: level
                ), range: paragraph)
            location = paragraph.location + paragraph.length
        }
        didChangeText()
    }

    /// Space-triggered conversions: "[ ]" forms → checkbox, "#" → heading,
    /// "N." → numbered item. On a line that is already a list item the
    /// typed marker replaces the existing one, so any list type turns into
    /// any other by typing its trigger right after the marker.
    private func convertLinePrefix() -> Bool {
        let ns = string as NSString
        let loc = selectedRange().location
        let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
        guard loc >= lineRange.location else { return false }
        var fullLine = ns.substring(with: lineRange)
        if fullLine.hasSuffix("\n") { fullLine.removeLast() }
        let markerLen = markerLength(of: fullLine)
        guard loc - lineRange.location >= markerLen else { return false }
        let typed = ns.substring(
            with: NSRange(
                location: lineRange.location + markerLen,
                length: loc - lineRange.location - markerLen
            ))
        // Replacements swallow the existing marker along with the trigger.
        let fullRange = NSRange(location: lineRange.location, length: loc - lineRange.location)
        let existing =
            textStorage?.attribute(.paragraphStyle, at: lineRange.location, effectiveRange: nil) as? NSParagraphStyle
        let level = indentLevel(of: existing, isList: markerLen > 0)

        // Checkbox conversion waits for the CLOSING bracket — converting at
        // "[" would make "[x]" untypeable. Bare bracket forms need an
        // existing marker; on plain text the leading "- " is required.
        let boxForms: [String: Bool] = [
            "[ ]": false, "[]": false,
            "[x]": true, "[X]": true, "[ x]": true, "[ X]": true,
        ]
        let boxTyped = typed.hasPrefix("- ") ? String(typed.dropFirst(2)) : typed
        if let checked = boxForms[boxTyped], typed.hasPrefix("- ") || markerLen > 0 {
            replace(fullRange, with: checkboxMarker(checked: checked, level: level))
            return true
        }
        if typed == "#" || typed == "##" || typed == "###" {
            replace(fullRange, with: NSAttributedString(string: ""))
            var attrs = bodyAttributes
            attrs[.font] = headingFont(typed.count)
            attrs[.paragraphStyle] = headingParagraph
            typingAttributes = attrs
            return true
        }
        // "- "/"* " on a plain line stays deferred (convertDashIfPending);
        // on an existing list item it switches the item to a bullet now.
        if typed == "-" || typed == "*", markerLen > 0 {
            replace(fullRange, with: NSAttributedString(string: "•\t", attributes: listAttributes(level: level)))
            return true
        }
        // Ordered list: a number followed by "." and a space. On a plain line
        // only "1." starts one — see StickyNoteMarkup.startsOrderedList.
        if StickyNoteMarkup.startsOrderedList(typed, continuingExistingItem: markerLen > 0) {
            replace(fullRange, with: NSAttributedString(string: typed + "\t", attributes: listAttributes(level: level)))
            return true
        }
        return false
    }

    /// Pressing return inside a link's text opens the link. Both neighbors
    /// of the insertion point must carry the same link, so the boundaries
    /// (just before or just after the link) still insert a newline.
    private func openLinkAtCursorInstead() -> Bool {
        guard selectedRange().length == 0, let storage = textStorage else { return false }
        let loc = selectedRange().location
        guard loc > 0, loc < storage.length,
            let before = storage.attribute(.link, at: loc - 1, effectiveRange: nil),
            let after = storage.attribute(.link, at: loc, effectiveRange: nil)
        else { return false }
        let a = (after as? URL)?.absoluteString ?? (after as? String ?? "")
        let b = (before as? URL)?.absoluteString ?? (before as? String ?? "")
        guard !a.isEmpty, a == b, let url = URL(string: a) else { return false }
        NSWorkspace.shared.open(url)
        return true
    }

    /// A line whose full content is "- " becomes a bullet the moment a
    /// non-bracket character follows — no interstitial bullet while a
    /// checkbox is being typed.
    private func convertDashIfPending() {
        let ns = string as NSString
        let loc = selectedRange().location
        let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
        guard loc - lineRange.location == 2 else { return }
        let prefixRange = NSRange(location: lineRange.location, length: 2)
        let prefix = ns.substring(with: prefixRange)
        guard prefix == "- " || prefix == "* " else { return }
        let existing =
            textStorage?.attribute(.paragraphStyle, at: lineRange.location, effectiveRange: nil) as? NSParagraphStyle
        let level = indentLevel(of: existing, isList: false)
        replace(prefixRange, with: NSAttributedString(string: "•\t", attributes: listAttributes(level: level)))
    }

    /// Typing "-" or "*" right after a fresh checkbox marker switches the
    /// item to a bullet — changing your mind shouldn't need deleting.
    private func convertCheckboxToBullet() -> Bool {
        guard let storage = textStorage else { return false }
        let ns = string as NSString
        let loc = selectedRange().location
        let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
        let marker = ns.substring(
            with: NSRange(location: lineRange.location, length: min(2, ns.length - lineRange.location)))
        guard loc - lineRange.location == 2,
            StickyNoteMarkup.separators.contains(where: { marker == StickyNoteMarkup.checkboxCharacter + $0 }),
            storage.attribute(.attachment, at: lineRange.location, effectiveRange: nil) is CheckboxAttachment
        else { return false }
        let markerRange = NSRange(location: lineRange.location, length: 2)
        let existing =
            storage.attribute(.paragraphStyle, at: lineRange.location, effectiveRange: nil) as? NSParagraphStyle
        let level = indentLevel(of: existing, isList: true)
        replace(markerRange, with: NSAttributedString(string: "•\t", attributes: listAttributes(level: level)))
        return true
    }

    /// Pressing return on a line that is nothing but a list marker deletes
    /// the marker (ending the list) rather than continuing it.
    private func removeBareListMarker() -> Bool {
        let ns = string as NSString
        let loc = selectedRange().location
        let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
        var content = ns.substring(with: lineRange)
        if content.hasSuffix("\n") { content.removeLast() }
        guard StickyNoteMarkup.isBareMarker(content) else { return false }
        let deleteRange = NSRange(location: lineRange.location, length: (content as NSString).length)
        replace(deleteRange, with: NSAttributedString(string: ""))
        typingAttributes = bodyAttributes
        return true
    }

    /// A line reading exactly "---" becomes a dim horizontal rule on return.
    /// Typing attributes for text inside a code chip.
    private var codeTypingAttributes: [NSAttributedString.Key: Any] {
        var attrs = bodyAttributes
        attrs.merge(NoteMarkdown.codeAttributes(font: defaultFont, textColor: defaultColor)) { _, new in new }
        return attrs
    }

    /// Three backticks at the head of a line open a block: the markers go,
    /// and what is typed from there is code until the block is left.
    private func convertCodeFence() -> Bool {
        guard selectedRange().length == 0, let storage = textStorage else { return false }
        let ns = storage.string as NSString
        let caret = selectedRange().location
        let lineRange = ns.lineRange(for: NSRange(location: caret, length: 0))
        var line = ns.substring(with: lineRange)
        if line.hasSuffix("\n") { line.removeLast() }
        guard line == "``", caret == lineRange.location + 2 else { return false }

        replace(NSRange(location: lineRange.location, length: 2), with: NSAttributedString(string: ""))
        typingAttributes = codeTypingAttributes
        return true
    }

    /// Whether Return should stay in a code block, leave it, or has nothing
    /// to do with one.
    ///
    /// Leaving on an empty line is the same convention the lists use: an
    /// empty bullet ends the list, an empty code line ends the block. One
    /// rule to learn instead of two.
    private func codeBlockContinuation() -> Bool? {
        guard let storage = textStorage else { return nil }
        let ns = storage.string as NSString
        let lineRange = ns.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        var line = ns.substring(with: lineRange)
        if line.hasSuffix("\n") { line.removeLast() }
        let contentLength = (line as NSString).length

        if contentLength == 0 {
            return typingAttributes[.backgroundColor] != nil ? false : nil
        }
        guard storage.attribute(.backgroundColor, at: lineRange.location, effectiveRange: nil) != nil,
            NoteMarkdown.isEntirelyCode(
                storage.attributedSubstring(from: NSRange(location: lineRange.location, length: contentLength)))
        else { return nil }
        return true
    }

    /// Typing the closing backtick of a code span converts it, the way the
    /// closing bracket converts a checkbox: both backticks disappear and what
    /// was between them becomes a chip.
    ///
    /// Converting on the opening backtick is impossible — at that point there
    /// is nothing to say a span was meant rather than a lone backtick — and
    /// waiting for anything later would leave the markers visible in a note
    /// that is not markdown.
    private func convertCodeSpan() -> Bool {
        guard let storage = textStorage else { return false }
        let ns = storage.string as NSString
        let caret = selectedRange().location
        guard selectedRange().length == 0 else { return false }

        let lineRange = ns.lineRange(for: NSRange(location: caret, length: 0))
        let line = ns.substring(with: lineRange)
        let offsetInLine = caret - lineRange.location
        guard let opening = StickyNoteMarkup.codeSpanOpening(closingAt: offsetInLine, in: line) else {
            return false
        }

        let contentStart = lineRange.location + opening + 1
        let content = ns.substring(with: NSRange(location: contentStart, length: caret - contentStart))
        let replaced = NSRange(location: lineRange.location + opening, length: caret - lineRange.location - opening)

        var attrs = codeTypingAttributes
        // The paragraph the span sits in keeps its own geometry; only the
        // characters change.
        attrs[.paragraphStyle] =
            storage.attribute(.paragraphStyle, at: lineRange.location, effectiveRange: nil) as? NSParagraphStyle
            ?? bodyParagraph

        replace(replaced, with: NSAttributedString(string: content, attributes: attrs))
        // Typing carries on outside the chip.
        typingAttributes = bodyAttributes
        return true
    }

    // MARK: Formatting bar

    /// The bar follows the selection. `stillSelecting` is the drag itself —
    /// showing a bar under the finger while it is still moving would put the
    /// thing being aimed at on top of the thing doing the aiming.
    override func setSelectedRanges(
        _ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool
    ) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        guard !stillSelecting else { return }
        updateFormatBar()
    }

    private func updateFormatBar() {
        let range = selectedRange()
        guard range.length > 0, window != nil else {
            formatBar.hide()
            return
        }
        let rect = firstRect(forCharacterRange: range, actualRange: nil)
        guard let window, rect.width > 0 || rect.height > 0 else {
            formatBar.hide()
            return
        }
        let inWindow = window.convertFromScreen(rect)
        formatBar.update(selectionRect: convert(inWindow, from: nil), visible: true)
    }

    override func resignFirstResponder() -> Bool {
        formatBar.hide()
        return super.resignFirstResponder()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { formatBar.hide() }
    }

    /// Bold and Italic exist in the Format menu through NSFontManager, which
    /// the bar cannot reach — its buttons must not take first responder, and
    /// addFontTrait works off the responder chain. So the trait is applied to
    /// the selection directly.
    @objc func formatBold(_ sender: Any?) { toggleTrait(.bold) }
    @objc func formatItalic(_ sender: Any?) { toggleTrait(.italic) }

    private func toggleTrait(_ trait: NSFontDescriptor.SymbolicTraits) {
        guard let storage = textStorage else { return }
        let range = selectedRange()
        guard range.length > 0, shouldChangeText(in: range, replacementString: nil) else { return }

        // Off only when every character already has it: a mixed selection
        // becomes uniformly styled, which is what every editor does.
        var allHaveIt = true
        storage.enumerateAttribute(.font, in: range) { value, _, stop in
            guard let font = value as? NSFont else { return }
            if !font.fontDescriptor.symbolicTraits.contains(trait) {
                allHaveIt = false
                stop.pointee = true
            }
        }

        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            guard let font = value as? NSFont else { return }
            var traits = font.fontDescriptor.symbolicTraits
            if allHaveIt { traits.remove(trait) } else { traits.insert(trait) }
            let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
            storage.addAttribute(
                .font, value: NSFont(descriptor: descriptor, size: font.pointSize) ?? font, range: subrange)
        }
        didChangeText()
        updateFormatBar()
    }

    /// Makes the selection a code chip, or takes it back out of one.
    @objc func toggleCodeSpan(_ sender: Any?) {
        guard let storage = textStorage else { return }
        let range = selectedRange()
        guard range.length > 0, shouldChangeText(in: range, replacementString: nil) else { return }

        let isCode = storage.attribute(.backgroundColor, at: range.location, effectiveRange: nil) != nil
        if isCode {
            storage.removeAttribute(.backgroundColor, range: range)
            storage.addAttribute(.font, value: defaultFont, range: range)
        } else {
            for (key, value) in NoteMarkdown.codeAttributes(font: defaultFont, textColor: defaultColor) {
                storage.addAttribute(key, value: value, range: range)
            }
        }
        didChangeText()
        updateFormatBar()
    }

    // MARK: Slash commands

    /// A slash at the head of a line offers the line kinds as a menu.
    ///
    /// Only at the head: "and/or" is a word, and a menu that appeared inside
    /// one would be worse than no menu. After a list marker counts as the
    /// head — changing a bullet into a to-do is exactly what this is for.
    private func showCommandMenu() -> Bool {
        guard selectedRange().length == 0, let window else { return false }
        let ns = string as NSString
        let caret = selectedRange().location
        let lineRange = ns.lineRange(for: NSRange(location: caret, length: 0))
        var line = ns.substring(with: lineRange)
        if line.hasSuffix("\n") { line.removeLast() }
        guard caret - lineRange.location == markerLength(of: line) else { return false }

        let menu = NSMenu()
        menu.autoenablesItems = false
        for command in StickyNoteCommand.allCases {
            let item = NSMenuItem(
                title: command.title, action: #selector(runCommand(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = command.rawValue
            item.image = NSImage(systemSymbolName: command.symbolName, accessibilityDescription: nil)
            menu.addItem(item)
        }

        // Anchored under the caret so the menu reads as belonging to the line
        // being typed rather than to the widget.
        let caretRect = firstRect(forCharacterRange: NSRange(location: caret, length: 0), actualRange: nil)
        let inWindow = window.convertFromScreen(caretRect)
        let point = convert(NSPoint(x: inWindow.minX, y: inWindow.minY), from: nil)
        menu.popUp(positioning: nil, at: point, in: self)
        return true
    }

    @objc private func runCommand(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
            let command = StickyNoteCommand(rawValue: raw)
        else { return }
        apply(command)
    }

    private func apply(_ command: StickyNoteCommand) {
        let ns = string as NSString
        let caret = selectedRange().location
        let lineRange = ns.lineRange(for: NSRange(location: caret, length: 0))
        var line = ns.substring(with: lineRange)
        if line.hasSuffix("\n") { line.removeLast() }
        let markerLen = markerLength(of: line)
        let existing =
            textStorage?.attribute(.paragraphStyle, at: lineRange.location, effectiveRange: nil) as? NSParagraphStyle
        let level = indentLevel(of: existing, isList: markerLen > 0)
        // Whatever marker the line already carries is replaced, not added to.
        let markerRange = NSRange(location: lineRange.location, length: markerLen)

        switch command {
        case .todo:
            replace(markerRange, with: checkboxMarker(checked: false, level: level))
        case .bullet, .numbered:
            guard let marker = command.marker else { return }
            replace(markerRange, with: NSAttributedString(string: marker, attributes: listAttributes(level: level)))
        case .heading1, .heading2, .heading3:
            guard let heading = command.headingLevel else { return }
            applyHeading(heading, to: lineRange, markerRange: markerRange)
        case .body:
            resetToBodyText(nil)
        case .divider:
            setSelectedRange(NSRange(location: lineRange.location, length: markerLen))
            _ = convertHorizontalRuleText()
        case .code:
            insertCodePlaceholder()
        case .date:
            insertText(
                NSAttributedString(string: StickyNoteCommand.todaysDate(), attributes: bodyAttributes),
                replacementRange: selectedRange())
        }
    }

    /// Restyles the line as a heading and leaves typing set to continue it.
    private func applyHeading(_ level: Int, to lineRange: NSRange, markerRange: NSRange) {
        guard let storage = textStorage else { return }
        // A heading is not a list item, so any marker goes with the change.
        if markerRange.length > 0 { replace(markerRange, with: NSAttributedString(string: "")) }

        let ns = storage.string as NSString
        let paragraph = ns.lineRange(for: NSRange(location: markerRange.location, length: 0))
        var contentLength = paragraph.length
        if ns.substring(with: paragraph).hasSuffix("\n") { contentLength -= 1 }

        var attrs = bodyAttributes
        attrs[.font] = headingFont(level)
        attrs[.paragraphStyle] = headingParagraph
        if contentLength > 0 {
            guard shouldChangeText(in: paragraph, replacementString: nil) else { return }
            storage.setAttributes(attrs, range: NSRange(location: paragraph.location, length: contentLength))
            didChangeText()
        }
        typingAttributes = attrs
    }

    /// The whole line becomes a rule, whatever was on it.
    private func convertHorizontalRuleText() -> Bool {
        let ns = string as NSString
        let lineRange = ns.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        var attrs = bodyAttributes
        attrs[.foregroundColor] = defaultColor.withAlphaComponent(0.35)
        var contentLength = lineRange.length
        if ns.substring(with: lineRange).hasSuffix("\n") { contentLength -= 1 }
        replace(
            NSRange(location: lineRange.location, length: contentLength),
            with: NSAttributedString(string: String(repeating: "\u{2500}", count: 24), attributes: attrs))
        typingAttributes = bodyAttributes
        return true
    }

    /// A chip with a word in it, selected, so typing replaces it. An empty
    /// chip would be invisible and impossible to aim at.
    private func insertCodePlaceholder() {
        let attrs = codeTypingAttributes
        let start = selectedRange().location
        insertText(NSAttributedString(string: "code", attributes: attrs), replacementRange: selectedRange())
        setSelectedRange(NSRange(location: start, length: 4))
        typingAttributes = attrs
    }

    private func convertHorizontalRule() -> Bool {
        let ns = string as NSString
        let loc = selectedRange().location
        let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
        let line = ns.substring(with: lineRange).trimmingCharacters(in: .newlines)
        guard line == "---" else { return false }
        var attrs = bodyAttributes
        attrs[.foregroundColor] = defaultColor.withAlphaComponent(0.35)
        let rule = NSMutableAttributedString(
            string: String(repeating: "─", count: 24) + "\n", attributes: attrs
        )
        replace(lineRange, with: rule)
        typingAttributes = bodyAttributes
        return true
    }

    /// Pressing return on a bullet/checkbox line continues the list; on an
    /// empty list line it ends it (handled by the caller inserting nothing —
    /// the empty marker line stays until deleted, matching most editors).
    private func listContinuation() -> NSAttributedString? {
        let ns = string as NSString
        let loc = selectedRange().location
        let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
        var line = ns.substring(with: lineRange)
        if line.hasSuffix("\n") { line.removeLast() }
        func hasContent(after marker: String) -> Bool {
            !line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces).isEmpty
        }
        // The new item continues at the same indent level as the current one.
        let existing =
            lineRange.length > 0
            ? textStorage?.attribute(.paragraphStyle, at: lineRange.location, effectiveRange: nil) as? NSParagraphStyle
            : nil
        let level = indentLevel(of: existing, isList: true)
        for sep in StickyNoteMarkup.separators {
            if line.hasPrefix("•" + sep) {
                return hasContent(after: "•" + sep)
                    ? NSAttributedString(string: "•\t", attributes: listAttributes(level: level)) : nil
            }
            if line.hasPrefix("\u{FFFC}" + sep) {
                return hasContent(after: "\u{FFFC}" + sep) ? checkboxMarker(checked: false, level: level) : nil
            }
        }
        // Numbered: "N.<tab>" continues as "N+1.<tab>".
        if let tab = line.firstIndex(of: "\t"), line[..<tab].hasSuffix("."),
            let n = Int(line[..<tab].dropLast())
        {
            return hasContent(after: String(line[...tab]))
                ? NSAttributedString(string: "\(n + 1).\t", attributes: listAttributes(level: level)) : nil
        }
        return nil
    }

    private func replace(_ range: NSRange, with attributed: NSAttributedString) {
        guard shouldChangeText(in: range, replacementString: attributed.string) else { return }
        textStorage?.replaceCharacters(in: range, with: attributed)
        didChangeText()
    }

    // MARK: Checkbox toggling

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        for candidate in [index, index - 1] where candidate >= 0 && candidate < (textStorage?.length ?? 0) {
            if let box = textStorage?.attribute(.attachment, at: candidate, effectiveRange: nil) as? CheckboxAttachment
            {
                let range = NSRange(location: candidate, length: 1)
                guard shouldChangeText(in: range, replacementString: nil) else { break }
                textStorage?.replaceCharacters(in: range, with: toggledBox(box, at: candidate))
                didChangeText()
                return
            }
        }
        super.mouseDown(with: event)
    }

    /// Format > Toggle Checked (Cmd+Return): flips the checkbox of every
    /// checkbox line the caret or selection touches; other lines are left
    /// alone. Same write path as clicking the box.
    @objc func toggleChecked(_ sender: Any?) {
        guard let storage = textStorage, storage.length > 0 else { return }
        let ns = string as NSString
        let lines = ns.lineRange(for: selectedRange())
        var location = lines.location
        while location < max(NSMaxRange(lines), lines.location + 1), location < ns.length {
            let paragraph = ns.lineRange(for: NSRange(location: location, length: 0))
            if paragraph.length > 0,
                let box = storage.attribute(.attachment, at: paragraph.location, effectiveRange: nil)
                    as? CheckboxAttachment
            {
                let range = NSRange(location: paragraph.location, length: 1)
                if shouldChangeText(in: range, replacementString: nil) {
                    storage.replaceCharacters(in: range, with: toggledBox(box, at: paragraph.location))
                    didChangeText()
                }
            }
            location = paragraph.location + paragraph.length
        }
    }

    // MARK: Strikethrough (Format menu)

    @objc func toggleStrikethrough(_ sender: Any?) {
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage else {
            let current = typingAttributes[.strikethroughStyle] as? Int ?? 0
            typingAttributes[.strikethroughStyle] = current == 0 ? NSUnderlineStyle.single.rawValue : 0
            return
        }
        guard shouldChangeText(in: range, replacementString: nil) else { return }
        let current = storage.attribute(.strikethroughStyle, at: range.location, effectiveRange: nil) as? Int ?? 0
        if current == 0 {
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        } else {
            storage.removeAttribute(.strikethroughStyle, range: range)
        }
        didChangeText()
    }

    // MARK: Link paste

    override func paste(_ sender: Any?) {
        if pasteImage() { return }
        guard
            let pasted = NSPasteboard.general.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            isLink(pasted)
        else {
            if pasteAsMarkdown() { return }
            super.paste(sender)
            return
        }

        let range = selectedRange()
        if range.length > 0 {
            // Slack-style: the selected words become the link title.
            guard shouldChangeText(in: range, replacementString: nil) else { return }
            textStorage?.addAttribute(.link, value: pasted, range: range)
            didChangeText()
        } else if let title = Self.promptForTitle(defaultTitle: URL(string: pasted)?.host ?? "link") {
            var attrs = bodyAttributes
            attrs[.link] = pasted
            insertText(NSAttributedString(string: title, attributes: attrs), replacementRange: range)
            // Continued typing must not extend the link.
            typingAttributes[.link] = nil
        }
    }

    /// An image on the pasteboard is written beside the note and referenced
    /// from it.
    ///
    /// Refusing is a real outcome: data of a kind this app cannot identify is
    /// not written under a guessed name, and the paste falls through to
    /// whatever else the pasteboard holds — usually the text a copied image
    /// came with.
    private func pasteImage() -> Bool {
        let board = NSPasteboard.general
        guard let writeMedia, let data = imageData(on: board), let name = writeMedia(data) else { return false }
        guard let attachment = MediaAttachment.make(filename: name, data: data) else { return false }

        let drawn = NSMutableAttributedString(attachment: attachment)
        drawn.addAttributes(
            [.font: defaultFont, .link: NoteMedia.link(forFile: name)],
            range: NSRange(location: 0, length: drawn.length))
        insertText(drawn, replacementRange: selectedRange())
        // Continued typing is text, not part of the image's reference.
        typingAttributes = bodyAttributes
        return true
    }

    /// Image bytes from the pasteboard, preferring what was actually copied
    /// over a rendering of it: a file dragged in keeps its own encoding, and
    /// re-encoding a PNG as TIFF makes it several times larger for nothing.
    private func imageData(on board: NSPasteboard) -> Data? {
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            as? [URL]
        {
            for url in urls {
                guard let data = try? Data(contentsOf: url), NoteMedia.fileExtension(for: data) != nil else {
                    continue
                }
                return data
            }
        }
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = board.data(forType: type), NoteMedia.fileExtension(for: data) != nil {
                return data
            }
        }
        return nil
    }

    private func isLink(_ s: String) -> Bool { StickyNoteMarkup.isWebLink(s) }

    /// Markdown on the pasteboard arrives as a note rather than as the
    /// characters someone else's editor used to describe one.
    ///
    /// Rich text on the pasteboard is left alone: it already carries the
    /// styling, and reading its plain-text fallback as markdown would throw
    /// that away to guess at it.
    private func pasteAsMarkdown() -> Bool {
        let board = NSPasteboard.general
        guard board.data(forType: .rtf) == nil, board.data(forType: .rtfd) == nil,
            let text = board.string(forType: .string),
            NoteMarkdown.looksLikeMarkdown(text)
        else { return false }

        let converted = NoteMarkdown.attributed(
            fromMarkdown: text, baseFont: defaultFont, textColor: defaultColor)
        guard converted.length > 0 else { return false }
        insertText(converted, replacementRange: selectedRange())
        return true
    }

    /// The note as markdown, on the pasteboard: the selection when there is
    /// one, the whole note when there is not.
    @objc func copyAsMarkdown(_ sender: Any?) {
        guard let storage = textStorage else { return }
        let selection = selectedRange()
        let range = selection.length > 0 ? selection : NSRange(location: 0, length: storage.length)
        let markdown = NoteMarkdown.markdown(
            from: storage.attributedSubstring(from: range), baseFont: defaultFont)
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(markdown, forType: .string)
    }

    private static func promptForTitle(defaultTitle: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Name this link"
        alert.informativeText = "The note shows the title; the link stays underneath."
        alert.addButton(withTitle: "Add Link")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = defaultTitle
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let typed = field.stringValue.trimmingCharacters(in: .whitespaces)
        return typed.isEmpty ? defaultTitle : typed
    }
}

// MARK: - Drawn checkbox

/// Custom-drawn checkbox image the note renders in place of ☐/☑: a rounded
/// stroke square, filled with the note's accent plus a checkmark when done.
/// The attachment exists only in the view — serialization maps it back to
/// the glyph characters.
