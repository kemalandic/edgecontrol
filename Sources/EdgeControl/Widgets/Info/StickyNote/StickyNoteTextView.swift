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
    private var isNormalizing = false

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
        [.font: defaultFont, .foregroundColor: defaultColor,
         .paragraphStyle: bodyParagraph, .kern: noteKern]
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
        s.addAttribute(.paragraphStyle,
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
        applyParagraphSpacing()
        renumberOrderedLists()
        applyTracking()
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
            let existing = storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle
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
               let n = Int(line[..<tab].dropLast()) {
                let existing = storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle
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
        let str = (insertString as? String)
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
            let continuation = listContinuation()
            super.insertText(insertString, replacementRange: replacementRange)
            // A heading ends at the line break; typing resumes as body text.
            typingAttributes = bodyAttributes
            if let continuation {
                super.insertText(continuation, replacementRange: selectedRange())
            }
            return
        }

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
            typingAttributes[.paragraphStyle] = paragraphStyle(isHeading: false, isList: false, markerInset: 0, level: level)
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
            let existing = storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle
            let level = max(0, min(maxIndentLevel, indentLevel(of: existing, isList: isList) + delta))
            storage.addAttribute(.paragraphStyle, value: paragraphStyle(
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
        let typed = ns.substring(with: NSRange(
            location: lineRange.location + markerLen,
            length: loc - lineRange.location - markerLen
        ))
        // Replacements swallow the existing marker along with the trigger.
        let fullRange = NSRange(location: lineRange.location, length: loc - lineRange.location)
        let existing = textStorage?.attribute(.paragraphStyle, at: lineRange.location, effectiveRange: nil) as? NSParagraphStyle
        let level = indentLevel(of: existing, isList: markerLen > 0)

        // Checkbox conversion waits for the CLOSING bracket — converting at
        // "[" would make "[x]" untypeable. Bare bracket forms need an
        // existing marker; on plain text the leading "- " is required.
        let boxForms: [String: Bool] = ["[ ]": false, "[]": false,
                                        "[x]": true, "[X]": true, "[ x]": true, "[ X]": true]
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
        let existing = textStorage?.attribute(.paragraphStyle, at: lineRange.location, effectiveRange: nil) as? NSParagraphStyle
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
        let marker = ns.substring(with: NSRange(location: lineRange.location, length: min(2, ns.length - lineRange.location)))
        guard loc - lineRange.location == 2,
              StickyNoteMarkup.separators.contains(where: { marker == StickyNoteMarkup.checkboxCharacter + $0 }),
              storage.attribute(.attachment, at: lineRange.location, effectiveRange: nil) is CheckboxAttachment
        else { return false }
        let markerRange = NSRange(location: lineRange.location, length: 2)
        let existing = storage.attribute(.paragraphStyle, at: lineRange.location, effectiveRange: nil) as? NSParagraphStyle
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
        let existing = lineRange.length > 0
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
           let n = Int(line[..<tab].dropLast()) {
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
            if let box = textStorage?.attribute(.attachment, at: candidate, effectiveRange: nil) as? CheckboxAttachment {
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
               let box = storage.attribute(.attachment, at: paragraph.location, effectiveRange: nil) as? CheckboxAttachment {
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
        guard let pasted = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            isLink(pasted)
        else {
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

    private func isLink(_ s: String) -> Bool { StickyNoteMarkup.isWebLink(s) }

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
