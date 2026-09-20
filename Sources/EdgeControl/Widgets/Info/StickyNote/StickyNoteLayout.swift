import AppKit

/// The geometry of a sticky note's lines: indents, tab stops, paragraph
/// spacing, marker alignment and heading sizes.
///
/// All of it is a function of the note's font, so none of it needs a text view
/// to compute. That matters most for one invariant: an indent level is never
/// stored, it is recovered from the geometry of the line's current style, so it
/// survives saves, loads and every re-normalisation pass. If the two halves of
/// that round trip ever disagree, nested lists quietly flatten — and there was
/// no way to check it from outside an editor.
struct StickyNoteLayout {
    let font: NSFont

    /// Tab/Shift-Tab will not nest deeper than this.
    let maxIndentLevel = 6

    init(font: NSFont) { self.font = font }

    /// Marker Felt and Noteworthy set their letters so tight on the small panel
    /// that they blur together; a little tracking keeps them legible.
    var kern: CGFloat {
        switch font.familyName {
        case "Marker Felt", "Noteworthy": return font.pointSize * 0.08
        default: return 0
        }
    }

    /// Column where list text begins; markers sit before a tab. Wide enough for
    /// a two-digit number and its dot, whatever the note font — a marker wider
    /// than its column would push the tab a full extra column to the right.
    var listTextIndent: CGFloat {
        let twoDigits = ("88." as NSString).size(withAttributes: [.font: font]).width
        return max((font.pointSize * 1.8).rounded(), (twoDigits + font.pointSize * 0.5).rounded())
    }

    /// One Tab/Shift-Tab step — the width of the list column, so nested list
    /// text lands exactly one column further in.
    var indentStep: CGFloat { listTextIndent }

    /// Markers right-align to a shared edge just before the text column: number
    /// dots line up regardless of digit count, the checkbox's right side sits
    /// on that edge, and the narrow bullet is centred over the checkbox.
    func markerInset(for line: String) -> CGFloat {
        let columnEnd = listTextIndent - font.pointSize * 0.45
        let boxWidth = font.pointSize * 1.2
        if line.hasPrefix(StickyNoteMarkup.checkboxCharacter + "\t") {
            return max(0, (columnEnd - boxWidth).rounded())
        }
        if line.hasPrefix("•\t") {
            let bulletWidth = ("•" as NSString).size(withAttributes: [.font: font]).width
            return max(0, (columnEnd - boxWidth + (boxWidth - bulletWidth) / 2).rounded())
        }
        guard let tab = line.firstIndex(of: "\t") else { return 0 }
        let width = (String(line[..<tab]) as NSString).size(withAttributes: [.font: font]).width
        return max(0, (columnEnd - width).rounded())
    }

    /// Single source of paragraph geometry: spacing rhythm per line kind plus
    /// the Tab/Shift-Tab indent level. List lines keep one shared text column
    /// (marker, tab, text) shifted right per level, with wrapped lines hanging
    /// under the text.
    func paragraphStyle(isHeading: Bool, isList: Bool, markerInset: CGFloat, level: Int) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        let indent = CGFloat(level) * indentStep
        if isHeading {
            p.paragraphSpacing = font.pointSize * 0.3
            p.paragraphSpacingBefore = font.pointSize * 0.5
            p.firstLineHeadIndent = indent
            p.headIndent = indent
        } else if isList {
            p.paragraphSpacing = font.pointSize * 0.22
            p.firstLineHeadIndent = indent + markerInset
            p.tabStops = [NSTextTab(textAlignment: .left, location: indent + listTextIndent)]
            p.defaultTabInterval = listTextIndent
            p.headIndent = indent + listTextIndent
        } else {
            p.paragraphSpacing = font.pointSize * 0.22
            p.firstLineHeadIndent = indent
            p.headIndent = indent
        }
        return p
    }

    /// The other half of the round trip: the level a style was built with.
    func indentLevel(of style: NSParagraphStyle?, isList: Bool) -> Int {
        guard let style else { return 0 }
        let base = isList
            ? (style.tabStops.first?.location ?? listTextIndent) - listTextIndent
            : style.firstLineHeadIndent
        return max(0, min(maxIndentLevel, Int((base / indentStep).rounded())))
    }

    func headingFont(_ level: Int) -> NSFont {
        let scale: CGFloat = level == 1 ? 1.6 : level == 2 ? 1.35 : 1.15
        let descriptor = font.fontDescriptor.withSymbolicTraits(
            font.fontDescriptor.symbolicTraits.union(.bold)
        )
        return NSFont(descriptor: descriptor, size: font.pointSize * scale)
            ?? .boldSystemFont(ofSize: font.pointSize * scale)
    }
}
