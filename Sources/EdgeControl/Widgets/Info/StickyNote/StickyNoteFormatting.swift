import AppKit

/// What the formatting commands do to the text, with no text view in sight.
///
/// Bold, strikethrough, code, body text and ticking a box are all the same
/// shape: take an attributed string and a range, change attributes over it.
/// Keeping that shape here means the editor is left with the parts that are
/// genuinely about being a view — the selection, undo registration, the menu
/// — and the decisions can be checked by handing over a string.
///
/// Every function answers whether it changed anything, so the caller knows
/// whether to register an undo step and tell its observers.
struct StickyNoteFormatting {
    let layout: StickyNoteLayout
    let defaultFont: NSFont
    let defaultColor: NSColor
    let accentColor: NSColor

    // MARK: - Traits

    /// Adds a trait, or takes it away when every character already has it.
    ///
    /// A mixed selection becomes uniformly styled rather than inverted
    /// character by character, which is what every editor does and what
    /// anybody dragging across a half-bold phrase expects.
    @discardableResult
    func toggle(
        _ trait: NSFontDescriptor.SymbolicTraits, in storage: NSMutableAttributedString, range: NSRange
    ) -> Bool {
        guard range.length > 0, NSMaxRange(range) <= storage.length else { return false }

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
        return true
    }

    @discardableResult
    func toggleStrikethrough(in storage: NSMutableAttributedString, range: NSRange) -> Bool {
        guard range.length > 0, NSMaxRange(range) <= storage.length else { return false }
        let current = storage.attribute(.strikethroughStyle, at: range.location, effectiveRange: nil) as? Int ?? 0
        if current == 0 {
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        } else {
            storage.removeAttribute(.strikethroughStyle, range: range)
        }
        return true
    }

    /// Makes the range a code chip, or takes it back out of one.
    @discardableResult
    func toggleCode(in storage: NSMutableAttributedString, range: NSRange) -> Bool {
        guard range.length > 0, NSMaxRange(range) <= storage.length else { return false }
        let isCode = storage.attribute(.backgroundColor, at: range.location, effectiveRange: nil) != nil
        if isCode {
            storage.removeAttribute(.backgroundColor, range: range)
            storage.addAttribute(.font, value: defaultFont, range: range)
        } else {
            for (key, value) in NoteMarkdown.codeAttributes(font: defaultFont, textColor: defaultColor) {
                storage.addAttribute(key, value: value, range: range)
            }
        }
        return true
    }

    /// Strips heading size, emphasis, underline and strikethrough, keeping
    /// links — the "put this back to how it started" command.
    @discardableResult
    func resetToBody(in storage: NSMutableAttributedString, range: NSRange) -> Bool {
        guard range.length > 0, NSMaxRange(range) <= storage.length else { return false }
        storage.addAttribute(.font, value: defaultFont, range: range)
        storage.addAttribute(
            .paragraphStyle,
            value: layout.paragraphStyle(isHeading: false, isList: false, markerInset: 0, level: 0),
            range: range)
        storage.removeAttribute(.strikethroughStyle, range: range)
        storage.removeAttribute(.underlineStyle, range: range)
        return true
    }

    // MARK: - Checkboxes

    /// The lines in `range` that carry a drawn checkbox, by the location of
    /// the box itself.
    ///
    /// Separated from the flipping so the caller can register one undo step
    /// per box and so this can be checked without one: a selection touching
    /// four lines of which two are to-dos must find exactly those two.
    func checkboxLocations(in storage: NSAttributedString, range: NSRange) -> [Int] {
        guard storage.length > 0 else { return [] }
        let text = storage.string as NSString
        let clamped = NSRange(
            location: min(range.location, text.length),
            length: min(range.length, max(0, text.length - min(range.location, text.length))))
        let lines = text.lineRange(for: clamped)

        var found: [Int] = []
        var location = lines.location
        while location < max(NSMaxRange(lines), lines.location + 1), location < text.length {
            let paragraph = text.lineRange(for: NSRange(location: location, length: 0))
            if paragraph.length > 0,
                storage.attribute(.attachment, at: paragraph.location, effectiveRange: nil)
                    is CheckboxAttachment
            {
                found.append(paragraph.location)
            }
            location = paragraph.location + paragraph.length
        }
        return found
    }

    /// The flipped replacement for the box at `location`, carrying over the
    /// paragraph style it is standing in.
    ///
    /// The carry-over is the point: a bare box has no style, and the
    /// normalizer would read that as indent level zero — outdenting the line
    /// every time somebody ticked it.
    func flippedCheckbox(at location: Int, in storage: NSAttributedString) -> NSAttributedString? {
        guard location < storage.length,
            let box = storage.attribute(.attachment, at: location, effectiveRange: nil) as? CheckboxAttachment
        else { return nil }

        let normalizer = StickyNoteNormalizer(
            layout: layout, defaultFont: defaultFont, defaultColor: defaultColor, accentColor: accentColor)
        let flipped = NSMutableAttributedString(
            attributedString: normalizer.checkbox(checked: !box.checked))
        if let style = storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) {
            flipped.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: flipped.length))
        }
        return flipped
    }
}
