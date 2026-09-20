import AppKit

/// Putting a line into a note without going to the note.
///
/// This is the difference between a widget and something used every day. A
/// thought arrives while another app is in front; the panel is across the
/// desk; and the cost of walking over to it is the reason the thought does
/// not get written down. A key from anywhere, a line, and it is in the note.
public enum QuickCapture {

    /// The note captures land in. A fixed id so the file is `inbox.rtf` and
    /// the widget picker has a stable thing to point at.
    public static let inboxNoteId = "inbox"
    public static let inboxTitle = "Inbox"

    /// The captured line, added to the note.
    ///
    /// Returns nil when there is nothing to add, which is the honest answer
    /// to an empty box — writing a blank line into the inbox would make the
    /// note grow every time somebody opened the window and thought better of
    /// it.
    public static func appending(
        _ line: String, to existing: NSAttributedString?, baseFont: NSFont, textColor: NSColor
    ) -> NSAttributedString? {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let layout = StickyNoteLayout(font: baseFont)
        let paragraph = layout.paragraphStyle(isHeading: false, isList: false, markerInset: 0, level: 0)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: baseFont, .foregroundColor: textColor, .paragraphStyle: paragraph,
        ]

        let out = NSMutableAttributedString()
        if let existing, existing.length > 0 {
            out.append(existing)
            out.append(NSAttributedString(string: "\n", attributes: attributes))
        } else {
            // A brand new inbox gets a heading, which is also what the note
            // index reads as its title — so it is recognisable in the picker
            // before anything has been captured into it.
            out.append(
                NSAttributedString(
                    string: inboxTitle,
                    attributes: [
                        .font: layout.headingFont(2), .foregroundColor: textColor,
                        .paragraphStyle: layout.paragraphStyle(
                            isHeading: true, isList: false, markerInset: 0, level: 0),
                    ]))
            out.append(NSAttributedString(string: "\n", attributes: attributes))
        }

        // Captured as a line, not as a task. Plenty of what lands here is a
        // thought rather than a thing to do, and turning a bullet into a
        // to-do in the note is one keystroke.
        out.append(NSAttributedString(string: text, attributes: attributes))
        return out
    }

    /// The font and colour a captured line is written in.
    ///
    /// The widget's own settings are not available here — the capture window
    /// does not know which widget, if any, will show the note — so it writes
    /// in the defaults the widget would have used. A widget configured
    /// differently reflows the note when it loads it.
    @MainActor
    public static func defaultFont() -> NSFont {
        RichStickyTextView.makeFont(family: "mono", size: 18)
    }

    public static func defaultTextColor() -> NSColor {
        StickyNotePalette.text("soft white")
    }
}
