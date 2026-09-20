import Foundation

/// A note, flattened for somewhere that cannot show a note.
///
/// The desktop widget lives in another process behind a sandbox: it cannot
/// read the notes folder, has no text system worth the name, and is redrawn
/// by the system on its own schedule. So what crosses into it is not a note —
/// it is the handful of lines worth glancing at, as plain words.
public enum NoteDigest {

    /// How many items a desktop widget can show before the rest is noise.
    /// A large widget fits about this many at a readable size; past that the
    /// answer is to open the note.
    public static let limit = 12

    /// The to-do lines of a note, unfinished first.
    ///
    /// Only checkbox lines. A note's prose is what makes it a note, and none
    /// of it belongs on a desktop tile — what somebody wants there is the
    /// list, which is the part with boxes.
    public static func items(fromPlainText text: String, limit: Int = limit) -> [WidgetNoteItem] {
        guard limit > 0 else { return [] }

        var items: [WidgetNoteItem] = []
        for (index, line) in text.components(separatedBy: .newlines).enumerated() {
            guard StickyNoteMarkup.marker(of: line) == .checkbox,
                StickyNoteMarkup.hasContentAfterMarker(line)
            else { continue }

            let markerLength = StickyNoteMarkup.markerLength(of: line)
            let body = (line as NSString).substring(from: markerLength)
                .trimmingCharacters(in: .whitespaces)
            guard !body.isEmpty else { continue }

            items.append(
                WidgetNoteItem(
                    // The line's position, which is stable while the note is
                    // not edited — and a widget redrawn between two edits is
                    // showing a stale note anyway.
                    id: "\(index)",
                    text: body,
                    done: line.hasPrefix(StickyNoteMarkup.checkedGlyph)))
        }

        // Unfinished first, each group in the order the note has them. What
        // is left to do is the reason to look, and the done ones are there
        // for the sense of progress rather than to be read.
        let unfinished = items.filter { !$0.done }
        let finished = items.filter(\.done)
        return Array((unfinished + finished).prefix(limit))
    }

    /// How a widget summarises the list in one line. Lives on the shared
    /// item so the tile and the panel cannot disagree about it.
    public static func progress(_ items: [WidgetNoteItem]) -> String? {
        WidgetNoteItem.progress(items)
    }
}
