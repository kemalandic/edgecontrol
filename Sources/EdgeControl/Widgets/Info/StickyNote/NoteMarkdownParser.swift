import AppKit

// Reading markdown into a note. The writing side is in NoteMarkdown.swift.

extension NoteMarkdown {

    /// Markdown as a note.
    ///
    /// Anything the grammar does not cover arrives as the text it was written
    /// as, which is the honest outcome: a blockquote pasted into a note shows
    /// up as "> quoted", exactly as if it had been typed. Dropping it would
    /// lose the words; inventing a style for it would invent something the
    /// editor cannot produce or edit.
    public static func attributed(
        fromMarkdown markdown: String, baseFont: NSFont, textColor: NSColor
    ) -> NSAttributedString {
        let layout = StickyNoteLayout(font: baseFont)
        let out = NSMutableAttributedString()
        let lines = markdown.components(separatedBy: .newlines)

        var insideFence = false
        // Separators go before each line rather than after it. Fence lines
        // are dropped, so counting from the end of the input would leave a
        // newline behind for every fence — and a separator written after a
        // heading carries the heading's font, which then votes on what the
        // body font is when the note is exported.
        var wroteALine = false

        func separate() {
            guard wroteALine else { return }
            out.append(NSAttributedString(string: "\n", attributes: [.font: baseFont, .foregroundColor: textColor]))
        }

        for rawLine in lines {
            // A fence line is the marker, not content: it opens or closes the
            // block and is never written into the note.
            if isFence(rawLine) {
                insideFence.toggle()
                continue
            }
            if insideFence {
                separate()
                out.append(fencedLine(rawLine, baseFont: baseFont, textColor: textColor, layout: layout))
                wroteALine = true
                continue
            }

            let (level, undented) = indentation(of: rawLine)
            let (kind, body) = parseLine(undented)

            let marker = markerText(for: kind)
            let isList = !marker.isEmpty
            let markerInset = isList ? layout.markerInset(for: marker) : 0
            let paragraph = layout.paragraphStyle(
                isHeading: isHeading(kind), isList: isList, markerInset: markerInset, level: level)

            let font = fontFor(kind, layout: layout, baseFont: baseFont)
            let line = NSMutableAttributedString()

            if isList {
                line.append(
                    NSAttributedString(string: marker, attributes: [.font: font, .foregroundColor: textColor]))
            }

            if kind == .rule {
                line.append(
                    NSAttributedString(
                        string: String(repeating: ruleCharacter, count: ruleLength),
                        attributes: [.font: font, .foregroundColor: textColor.withAlphaComponent(0.35)]))
            } else {
                for run in inlineRuns(body) {
                    line.append(attributedRun(run, font: font, textColor: textColor, baseFont: baseFont))
                }
            }

            line.addAttribute(
                .paragraphStyle, value: paragraph, range: NSRange(location: 0, length: line.length))
            separate()
            out.append(line)
            wroteALine = true
        }

        return out
    }

    /// Three or more backticks alone on a line.
    static func isFence(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count >= 3 && trimmed.allSatisfy { $0 == "`" }
    }

    /// A line inside a fence is characters, not markup. Nothing in it is
    /// parsed — that is the whole point of a fence.
    private static func fencedLine(
        _ line: String, baseFont: NSFont, textColor: NSColor, layout: StickyNoteLayout
    ) -> NSAttributedString {
        var attributes = codeAttributes(font: baseFont, textColor: textColor)
        attributes[.foregroundColor] = textColor
        attributes[.paragraphStyle] = layout.paragraphStyle(
            isHeading: false, isList: false, markerInset: 0, level: 0)
        return NSAttributedString(string: line, attributes: attributes)
    }

    // MARK: - Lines

    /// Levels are two spaces or one tab each, and anything in between rounds
    /// down — a list indented by three spaces is one level in, not one and a
    /// half.
    static func indentation(of line: String) -> (level: Int, rest: String) {
        var spaces = 0
        var index = line.startIndex
        while index < line.endIndex {
            if line[index] == " " {
                spaces += 1
            } else if line[index] == "\t" {
                spaces += indentUnit.count
            } else {
                break
            }
            index = line.index(after: index)
        }
        let level = min(StickyNoteLayout(font: .systemFont(ofSize: 12)).maxIndentLevel, spaces / indentUnit.count)
        return (level, String(line[index...]))
    }

    static func parseLine(_ line: String) -> (kind: LineKind, body: String) {
        if isMarkdownRule(line) { return (.rule, "") }

        if line.hasPrefix("#") {
            let hashes = line.prefix { $0 == "#" }
            let rest = line.dropFirst(hashes.count)
            if hashes.count <= 3, rest.hasPrefix(" ") {
                return (.heading(hashes.count), String(rest.dropFirst()))
            }
        }

        for bullet in ["- ", "* ", "+ "] where line.hasPrefix(bullet) {
            let rest = String(line.dropFirst(bullet.count))
            for (box, checked) in [("[ ] ", false), ("[x] ", true), ("[X] ", true)] where rest.hasPrefix(box) {
                return (.checkbox(checked), String(rest.dropFirst(box.count)))
            }
            // A task marker with nothing after it is still a task.
            for (box, checked) in [("[ ]", false), ("[x]", true), ("[X]", true)] where rest == box {
                return (.checkbox(checked), "")
            }
            return (.bullet, rest)
        }

        let digits = line.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count <= 9, let number = Int(digits) {
            let rest = line.dropFirst(digits.count)
            if rest.hasPrefix(". ") {
                return (.ordered(number), String(rest.dropFirst(2)))
            }
        }

        return (.plain, unescapingLeadingMarkup(line))
    }

    /// Three or more of the same rule character, and nothing else.
    static func isMarkdownRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return false }
        for character in ["-", "*", "_"] where trimmed.allSatisfy({ String($0) == character }) {
            return true
        }
        return isRule(trimmed)
    }

    static func unescapingLeadingMarkup(_ line: String) -> String {
        if line.hasPrefix("\\") { return String(line.dropFirst()) }
        let digits = line.prefix { $0.isNumber }
        if !digits.isEmpty, line.dropFirst(digits.count).hasPrefix("\\.") {
            return String(digits) + String(line.dropFirst(digits.count + 1))
        }
        return line
    }

    static func markerText(for kind: LineKind) -> String {
        switch kind {
        case .bullet: return "\u{2022}\t"
        case .checkbox(let checked):
            return (checked ? StickyNoteMarkup.checkedGlyph : StickyNoteMarkup.uncheckedGlyph) + "\t"
        case .ordered(let number): return "\(number).\t"
        case .heading, .rule, .plain: return ""
        }
    }

    static func isHeading(_ kind: LineKind) -> Bool {
        if case .heading = kind { return true }
        return false
    }

    private static func fontFor(_ kind: LineKind, layout: StickyNoteLayout, baseFont: NSFont) -> NSFont {
        if case .heading(let level) = kind { return layout.headingFont(level) }
        return baseFont
    }

    /// How a code span is drawn, in one place: the editor stamps this when a
    /// span is typed, the reader stamps it when one is pasted, and the writer
    /// reads it back to put the backticks in again.
    ///
    /// The chip is the part that matters. The note's own font is monospaced
    /// by default, so a monospaced run is not on its own a code span.
    static func codeAttributes(font: NSFont, textColor: NSColor) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular),
            .backgroundColor: textColor.withAlphaComponent(0.15),
        ]
    }

    // MARK: - Inline

    struct InlineStyle: OptionSet {
        let rawValue: Int
        static let bold = InlineStyle(rawValue: 1 << 0)
        static let italic = InlineStyle(rawValue: 1 << 1)
        static let strikethrough = InlineStyle(rawValue: 1 << 2)
        static let code = InlineStyle(rawValue: 1 << 3)
    }

    struct InlineRun: Equatable {
        var text: String
        var style: InlineStyle
        var link: String?

        static func == (a: InlineRun, b: InlineRun) -> Bool {
            a.text == b.text && a.style.rawValue == b.style.rawValue && a.link == b.link
        }
    }

    /// Splits a line into styled runs.
    ///
    /// Markers that never close are text: "2 * 3 * 4" is arithmetic, and a
    /// reader that treated the first `*` as the start of emphasis would eat
    /// the rest of the line. So every toggle has to find its partner before
    /// it counts as markup.
    static func inlineRuns(_ text: String, link: String? = nil) -> [InlineRun] {
        let characters = Array(text)
        var runs: [InlineRun] = []
        var buffer = ""
        var style: InlineStyle = []
        var index = 0

        func flush() {
            guard !buffer.isEmpty else { return }
            runs.append(InlineRun(text: buffer, style: style, link: link))
            buffer = ""
        }

        func matches(_ token: String, at position: Int) -> Bool {
            let token = Array(token)
            guard position + token.count <= characters.count else { return false }
            return Array(characters[position..<(position + token.count)]) == token
        }

        func closes(_ token: String, from position: Int) -> Bool {
            var scan = position
            while scan < characters.count {
                if characters[scan] == "\\" {
                    scan += 2
                    continue
                }
                if matches(token, at: scan) { return true }
                scan += 1
            }
            return false
        }

        while index < characters.count {
            let character = characters[index]

            if character == "\\", index + 1 < characters.count {
                buffer.append(characters[index + 1])
                index += 2
                continue
            }

            if character == "`", let close = closingBacktick(characters, from: index + 1) {
                flush()
                runs.append(
                    InlineRun(
                        text: String(characters[(index + 1)..<close]), style: style.union(.code), link: link))
                index = close + 1
                continue
            }

            // An image is a link with a bang in front of it, and it is read
            // before the link branch so the bang is not left behind as text.
            if character == "!", index + 1 < characters.count, characters[index + 1] == "[",
                let parsed = parseLink(characters, from: index + 1)
            {
                flush()
                let name = mediaFilename(in: parsed.url)
                runs.append(
                    InlineRun(
                        text: parsed.title.isEmpty ? (name ?? parsed.url) : parsed.title,
                        style: style,
                        link: name.map { NoteMedia.link(forFile: $0) } ?? parsed.url))
                index = parsed.end
                continue
            }

            if character == "[", let parsed = parseLink(characters, from: index) {
                flush()
                runs.append(
                    contentsOf: inlineRuns(parsed.title, link: parsed.url).map { inner in
                        InlineRun(text: inner.text, style: inner.style.union(style), link: parsed.url)
                    })
                index = parsed.end
                continue
            }

            // Bold before italic, or "**" reads as two italics opening in a
            // row and the line comes back with the asterisks still in it.
            if let token = ["**", "__"].first(where: { matches($0, at: index) }),
                style.contains(.bold) || closes(token, from: index + token.count)
            {
                flush()
                style.formSymmetricDifference(.bold)
                index += token.count
                continue
            }

            if matches("~~", at: index), style.contains(.strikethrough) || closes("~~", from: index + 2) {
                flush()
                style.formSymmetricDifference(.strikethrough)
                index += 2
                continue
            }

            if character == "*" || character == "_" {
                let token = String(character)
                if style.contains(.italic) || closes(token, from: index + 1) {
                    flush()
                    style.formSymmetricDifference(.italic)
                    index += 1
                    continue
                }
            }

            buffer.append(character)
            index += 1
        }

        flush()
        return runs
    }

    /// The note's own image a markdown path points at, if it points at one.
    ///
    /// A path with a scheme is somewhere else entirely — an image on the web
    /// is read as a link, because there is no file beside the note to draw
    /// and inventing one would be worse than saying what it is.
    static func mediaFilename(in path: String) -> String? {
        guard !path.contains("://"), !path.hasPrefix("data:") else { return nil }
        if let direct = NoteMedia.file(fromLink: path) { return direct }
        guard !path.contains(":") else { return nil }
        let name = (path as NSString).lastPathComponent
        return NoteMedia.isSafeFilename(name) && !(name as NSString).pathExtension.isEmpty ? name : nil
    }

    private static func closingBacktick(_ characters: [Character], from start: Int) -> Int? {
        var scan = start
        while scan < characters.count {
            if characters[scan] == "`" { return scan }
            scan += 1
        }
        return nil
    }

    private static func parseLink(_ characters: [Character], from start: Int) -> (title: String, url: String, end: Int)?
    {
        var scan = start + 1
        var title = ""
        while scan < characters.count, characters[scan] != "]" {
            if characters[scan] == "\\", scan + 1 < characters.count {
                title.append(characters[scan])
                title.append(characters[scan + 1])
                scan += 2
                continue
            }
            title.append(characters[scan])
            scan += 1
        }
        guard scan < characters.count, characters[scan] == "]",
            scan + 1 < characters.count, characters[scan + 1] == "("
        else { return nil }

        scan += 2
        var url = ""
        while scan < characters.count, characters[scan] != ")" {
            url.append(characters[scan])
            scan += 1
        }
        guard scan < characters.count, !url.isEmpty else { return nil }
        return (title, url, scan + 1)
    }

    private static func attributedRun(
        _ run: InlineRun, font: NSFont, textColor: NSColor, baseFont: NSFont
    ) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: textColor]

        if run.style.contains(.code) {
            attributes.merge(codeAttributes(font: font, textColor: textColor)) { _, new in new }
        } else {
            var traits = font.fontDescriptor.symbolicTraits
            if run.style.contains(.bold) { traits.insert(.bold) }
            if run.style.contains(.italic) { traits.insert(.italic) }
            let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
            attributes[.font] = NSFont(descriptor: descriptor, size: font.pointSize) ?? font
        }

        if run.style.contains(.strikethrough) {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if let link = run.link {
            attributes[.link] = link
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }

        return NSAttributedString(string: run.text, attributes: attributes)
    }
}
