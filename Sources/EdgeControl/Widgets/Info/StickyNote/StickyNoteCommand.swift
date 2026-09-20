import Foundation

/// The commands a slash offers at the start of a line.
///
/// Everything here can already be typed — "- " makes a bullet, "# " a
/// heading — but only if you know that. The panel is touch-first and often
/// reached without a keyboard in front of it, and a menu is the one way to
/// find a feature you have not been told about.
///
/// The list is a value rather than a stack of menu-building code so the one
/// thing that can quietly break is testable: a command that inserts a marker
/// the editor's own parser does not recognise produces a line that looks like
/// a list and behaves like prose.
public enum StickyNoteCommand: String, CaseIterable, Hashable, Sendable {
    case todo
    case bullet
    case numbered
    case heading1
    case heading2
    case heading3
    case code
    case divider
    case date
    case body

    public var title: String {
        switch self {
        case .todo: return "To-do"
        case .bullet: return "Bulleted List"
        case .numbered: return "Numbered List"
        case .heading1: return "Heading 1"
        case .heading2: return "Heading 2"
        case .heading3: return "Heading 3"
        case .code: return "Code"
        case .divider: return "Divider"
        case .date: return "Today's Date"
        case .body: return "Body Text"
        }
    }

    /// SF Symbol for the menu. Chosen to read at a glance on a small panel.
    public var symbolName: String {
        switch self {
        case .todo: return "checklist"
        case .bullet: return "list.bullet"
        case .numbered: return "list.number"
        case .heading1: return "textformat.size.larger"
        case .heading2: return "textformat.size"
        case .heading3: return "textformat.size.smaller"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .divider: return "minus"
        case .date: return "calendar"
        case .body: return "textformat"
        }
    }

    /// The marker this command puts at the head of the line, if it makes the
    /// line a list item. Written with the editor's own vocabulary, so the
    /// parser reads back what the command wrote.
    public var marker: String? {
        switch self {
        case .todo: return StickyNoteMarkup.uncheckedGlyph + "\t"
        case .bullet: return "\u{2022}\t"
        case .numbered: return "1.\t"
        case .heading1, .heading2, .heading3, .code, .divider, .date, .body: return nil
        }
    }

    /// The heading level this command sets, if it sets one.
    public var headingLevel: Int? {
        switch self {
        case .heading1: return 1
        case .heading2: return 2
        case .heading3: return 3
        default: return nil
        }
    }

    /// Whether the command replaces the line rather than restyling it.
    public var replacesLine: Bool {
        self == .divider
    }

    /// Today, written the way the rest of the system writes it — a note is
    /// read by the person who wrote it, in their own locale.
    public static func todaysDate(_ date: Date = Date(), locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
