import AppKit

/// Markdown in and out of a note.
///
/// The note itself is never markdown — it is rich text, and the editor's
/// "type `- ` and get a bullet" conversions happen at the keystroke. This is
/// the door to everything outside: text pasted in from somewhere else, a note
/// copied out into an issue or a commit message, and a folder of `.md` files.
///
/// The grammar is deliberately small — the subset the editor itself can
/// express, and nothing more. A note cannot hold a table or a blockquote, so
/// reading one would mean inventing a representation for something the user
/// can never type, and writing one would be dead code. What is here is
/// headings, the three kinds of list item with their nesting, horizontal
/// rules, links, and bold / italic / strikethrough / code spans.
public enum NoteMarkdown {

    /// One paragraph's worth of structure, which is all markdown needs to
    /// decide a line's prefix.
    enum LineKind: Equatable {
        case heading(Int)
        case bullet
        case checkbox(Bool)
        case ordered(Int)
        case rule
        case plain
    }

    /// The character a horizontal rule is drawn with, and how many of them the
    /// editor lays down. Recognising a rule on the way out means matching what
    /// `convertHorizontalRule` put in.
    static let ruleCharacter: Character = "\u{2500}"
    static let ruleLength = 24

    /// Two spaces per level, which is what every markdown renderer agrees a
    /// nested list item looks like.
    static let indentUnit = "  "

    // MARK: - Out

    /// The note as markdown.
    ///
    /// - Parameter baseFont: the note's body font. Headings are recognised by
    ///   being bigger than it, so without it there is no way to tell a heading
    ///   from a line someone enlarged by hand — which is the same thing.
    public static func markdown(from attributed: NSAttributedString, baseFont: NSFont) -> String {
        let layout = StickyNoteLayout(font: baseFont)
        let text = attributed.string as NSString
        var lines: [String] = []
        var location = 0

        while location < text.length {
            let paragraph = text.lineRange(for: NSRange(location: location, length: 0))
            location = paragraph.location + paragraph.length

            var line = text.substring(with: paragraph)
            var contentLength = paragraph.length
            while line.hasSuffix("\n") || line.hasSuffix("\r") {
                line.removeLast()
                contentLength -= 1
            }

            let kind = self.kind(of: line, in: attributed, at: paragraph.location, baseFont: baseFont)
            if kind == .rule {
                lines.append("---")
                continue
            }

            let markerLength = StickyNoteMarkup.markerLength(of: line)
            let style =
                contentLength > 0
                ? attributed.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil)
                    as? NSParagraphStyle
                : nil
            let level = layout.indentLevel(of: style, isList: markerLength > 0)

            let bodyRange = NSRange(
                location: paragraph.location + markerLength,
                length: max(0, contentLength - markerLength))
            // Emphasis is measured against the line's own font, not the
            // note's. A heading is already bold, and comparing it to the body
            // font would wrap every heading in asterisks: "# **Heading**".
            let lineFont = isHeadingKind(kind) ? layout.headingFont(headingNumber(kind)) : baseFont
            var body = inline(of: attributed.attributedSubstring(from: bodyRange), lineFont: lineFont)
            if kind == .plain { body = escapingLeadingMarkup(body) }

            lines.append(String(repeating: indentUnit, count: level) + prefix(for: kind) + body)
        }

        return lines.joined(separator: "\n")
    }

    static func prefix(for kind: LineKind) -> String {
        switch kind {
        case .heading(let level): return String(repeating: "#", count: level) + " "
        case .bullet: return "- "
        case .checkbox(let checked): return checked ? "- [x] " : "- [ ] "
        case .ordered(let number): return "\(number). "
        case .rule: return ""
        case .plain: return ""
        }
    }

    private static func kind(
        of line: String, in attributed: NSAttributedString, at location: Int, baseFont: NSFont
    ) -> LineKind {
        if isRule(line) { return .rule }
        switch StickyNoteMarkup.marker(of: line) {
        case .bullet: return .bullet
        case .checkbox:
            return .checkbox(line.hasPrefix(StickyNoteMarkup.checkedGlyph) || isCheckedAttachment(attributed, location))
        case .ordered(let number): return .ordered(number)
        case nil: break
        }
        if let level = headingLevel(in: attributed, at: location, baseFont: baseFont), !line.isEmpty {
            return .heading(level)
        }
        return .plain
    }

    static func isHeadingKind(_ kind: LineKind) -> Bool {
        if case .heading = kind { return true }
        return false
    }

    static func headingNumber(_ kind: LineKind) -> Int {
        if case .heading(let level) = kind { return level }
        return 0
    }

    static func isRule(_ line: String) -> Bool {
        !line.isEmpty && line.count >= 3 && line.allSatisfy { $0 == ruleCharacter }
    }

    private static func isCheckedAttachment(_ attributed: NSAttributedString, _ location: Int) -> Bool {
        guard location < attributed.length,
            let box = attributed.attribute(.attachment, at: location, effectiveRange: nil) as? CheckboxAttachment
        else { return false }
        return box.checked
    }

    /// Which heading a line is, by how much bigger than the body it is.
    ///
    /// The thresholds sit between the sizes `StickyNoteLayout.headingFont`
    /// produces (1.6, 1.35, 1.15) so a font that has been scaled — the note
    /// remembers absolute sizes, and Cmd+/− rescales everything — still lands
    /// on the level it was written as.
    static func headingLevel(in attributed: NSAttributedString, at location: Int, baseFont: NSFont) -> Int? {
        guard location < attributed.length,
            let font = attributed.attribute(.font, at: location, effectiveRange: nil) as? NSFont
        else { return nil }
        let ratio = font.pointSize / baseFont.pointSize
        if ratio >= 1.475 { return 1 }
        if ratio >= 1.25 { return 2 }
        if ratio >= 1.1 { return 3 }
        return nil
    }

    /// A plain line that begins with something markdown would read as markup
    /// gets a backslash, so reading it back gives the line that went in.
    static func escapingLeadingMarkup(_ line: String) -> String {
        guard let first = line.first else { return line }
        // `*`, `_`, backticks and backslashes are already escaped wherever
        // they appear, by escapingInline. Only these mean something purely
        // because they are first, and escaping a line that opens with real
        // emphasis — "**bold**" — would put a backslash in front of it.
        if first == "#" || first == "-" || first == ">" {
            return "\\" + line
        }
        // "1998. That was the year" is prose; "1. milk" is a list. Both are
        // escaped, because by the time a line reaches here the editor has
        // already decided it is not a list item.
        let digits = line.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count <= 9, line.dropFirst(digits.count).first == "." {
            return String(digits) + "\\" + String(line.dropFirst(digits.count))
        }
        return line
    }

    // MARK: - Recognising it

    /// Whether pasted text is worth reading as markdown.
    ///
    /// Deliberately hard to trigger. Emphasis alone does not count: prose is
    /// full of asterisks and underscores, and restyling a paragraph because
    /// someone wrote 3 * 4 would be worse than not converting at all. What
    /// counts is structure — a line that opens with a marker, or a link —
    /// because nobody types those by accident.
    public static func looksLikeMarkdown(_ text: String) -> Bool {
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if isMarkdownRule(line) { return true }
            if line.hasPrefix("# ") || line.hasPrefix("## ") || line.hasPrefix("### ") { return true }
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") { return true }
            // The same rule the editor applies at the keystroke: on a plain
            // line only "1." opens a list, because "1998. that was the year"
            // is a sentence. Reading is more forgiving — a list recognised by
            // its first item carries on at 2, 3, 4 — but recognising one is
            // not.
            let digits = line.prefix { $0.isNumber }
            if !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". "),
                StickyNoteMarkup.startsOrderedList(String(digits) + ".", continuingExistingItem: false)
            {
                return true
            }
        }
        return containsLink(text)
    }

    static func containsLink(_ text: String) -> Bool {
        let characters = Array(text)
        for index in characters.indices where characters[index] == "[" {
            guard let close = characters[index...].firstIndex(of: "]") else { continue }
            let afterClose = characters.index(after: close)
            if afterClose < characters.endIndex, characters[afterClose] == "(",
                characters[afterClose...].firstIndex(of: ")") != nil
            {
                return true
            }
        }
        return false
    }

    // MARK: - Inline, out

    /// Emphasis markers must touch the text they emphasise: `** bold **` is
    /// not bold in any renderer. So a run's outer whitespace is lifted out of
    /// the markers rather than wrapped by them.
    static func inline(of attributed: NSAttributedString, lineFont: NSFont) -> String {
        var out = ""
        let lineTraits = lineFont.fontDescriptor.symbolicTraits
        let full = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttributes(in: full) { attrs, range, _ in
            let raw = (attributed.string as NSString).substring(with: range)
            guard !raw.isEmpty else { return }

            // There is no `suffix(while:)`, and the run is only spaces either
            // way, so the tail is counted rather than sliced.
            let leading = String(raw.prefix { $0 == " " })
            let afterLeading = raw.dropFirst(leading.count)
            let trailingCount = afterLeading.reversed().prefix { $0 == " " }.count
            let trailing = String(repeating: " ", count: trailingCount)
            let core = String(afterLeading.dropLast(trailingCount))

            if core.isEmpty {
                out += raw
                return
            }

            var wrapped = escapingInline(core)
            let font = attrs[.font] as? NSFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []

            if attrs[.backgroundColor] != nil {
                // Code is literal: nothing inside a span is markup, so the
                // escaping applied above would show up as backslashes.
                wrapped = "`" + core + "`"
            } else {
                if traits.contains(.bold), !lineTraits.contains(.bold) { wrapped = "**" + wrapped + "**" }
                if traits.contains(.italic), !lineTraits.contains(.italic) { wrapped = "*" + wrapped + "*" }
                if let style = attrs[.strikethroughStyle] as? Int, style != 0 {
                    wrapped = "~~" + wrapped + "~~"
                }
            }

            if let link = linkString(attrs[.link]) {
                wrapped = "[" + wrapped + "](" + link + ")"
            }

            out += leading + wrapped + trailing
        }
        return out
    }

    static func linkString(_ value: Any?) -> String? {
        if let url = value as? URL { return url.absoluteString }
        if let string = value as? String, !string.isEmpty { return string }
        return nil
    }

    /// Characters that would otherwise be read back as markup.
    static func escapingInline(_ text: String) -> String {
        var out = ""
        for character in text {
            if character == "*" || character == "_" || character == "`" || character == "["
                || character == "]" || character == "\\" || character == "~"
            {
                out.append("\\")
            }
            out.append(character)
        }
        return out
    }
}
