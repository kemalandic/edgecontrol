import AppKit

/// Turning a note's to-do into a real reminder.
///
/// A checkbox in a note is a checkbox in a note: it is on the panel, and the
/// panel is on the desk. A reminder is on the phone, and it rings. Promotion
/// is the one-way door between them, for the items that turn out to matter
/// once they are written down.
///
/// One way on purpose. Keeping a note line and a reminder in step afterwards
/// is a synchronisation problem — two sources of truth, edits on both sides,
/// deletions to reconcile — and a note editor is the wrong place to grow one.
/// What is here does the thing people actually want: put it where it will
/// ring, and do not put it there twice.
public enum ReminderPromotion {

    /// The lines worth promoting, in the order they appear.
    ///
    /// A selection promotes every unfinished to-do it touches; a caret
    /// promotes the line it is on. Already-checked items are left alone —
    /// nobody needs reminding of something they have done — and so are
    /// markers with nothing written after them.
    public static func candidates(in attributed: NSAttributedString, range: NSRange) -> [String] {
        let text = attributed.string as NSString
        guard text.length > 0 else { return [] }

        let scan = NSRange(
            location: min(range.location, text.length),
            length: min(range.length, max(0, text.length - min(range.location, text.length))))
        let paragraphs = text.lineRange(for: scan)

        var titles: [String] = []
        var location = paragraphs.location
        let end = paragraphs.location + paragraphs.length

        while location < end {
            let paragraph = text.lineRange(for: NSRange(location: location, length: 0))
            location = paragraph.location + paragraph.length

            var line = text.substring(with: paragraph)
            while line.hasSuffix("\n") || line.hasSuffix("\r") { line.removeLast() }

            guard StickyNoteMarkup.marker(of: line) == .checkbox,
                !isChecked(line, in: attributed, at: paragraph.location),
                StickyNoteMarkup.hasContentAfterMarker(line)
            else { continue }

            let markerLength = StickyNoteMarkup.markerLength(of: line)
            let title = (line as NSString).substring(from: markerLength)
                .trimmingCharacters(in: .whitespaces)
            if !title.isEmpty { titles.append(title) }
        }

        return titles
    }

    /// A checkbox is a glyph in the file and a drawn attachment in the view,
    /// and promotion has to read both — the note on screen has attachments,
    /// the note on disk has glyphs.
    static func isChecked(_ line: String, in attributed: NSAttributedString, at location: Int) -> Bool {
        if line.hasPrefix(StickyNoteMarkup.checkedGlyph) { return true }
        guard location < attributed.length,
            let box = attributed.attribute(.attachment, at: location, effectiveRange: nil) as? CheckboxAttachment
        else { return false }
        return box.checked
    }

    /// The candidates that are not already waiting in Reminders.
    ///
    /// Matched on the text, ignoring case and surrounding space, because that
    /// is all the two have in common — a note line carries no identity a
    /// reminder could keep. It is a heuristic, and it is the one that stops
    /// the common mistake: pressing the key twice on the same list.
    public static func newTitles(_ candidates: [String], existing: [String]) -> [String] {
        let taken = Set(existing.map(normalised))
        var seen = Set<String>()
        var result: [String] = []

        for title in candidates {
            let key = normalised(title)
            guard !key.isEmpty, !taken.contains(key), !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(title)
        }
        return result
    }

    static func normalised(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// What to tell someone who cannot see the Reminders app from here.
    public static func summary(added: Int, skipped: Int) -> String {
        switch (added, skipped) {
        case (0, 0): return "No unfinished to-do on this line"
        case (0, _): return skipped == 1 ? "Already in Reminders" : "All \(skipped) already in Reminders"
        case (_, 0): return added == 1 ? "Added to Reminders" : "\(added) added to Reminders"
        default: return "\(added) added, \(skipped) already there"
        }
    }
}
