import Foundation

/// Reading the list markup at the head of a sticky-note line.
///
/// The editor recognises three kinds of list item and has to answer the same
/// questions about each of them from several places — how long the marker is,
/// whether the line has anything after it, what the next item's number should
/// be. That parsing was inline in the text view, where nothing could reach it
/// without an NSTextStorage and a window.
public enum StickyNoteMarkup {

    /// The attachment character AppKit substitutes for an inline image, which
    /// is how a drawn checkbox appears in the text.
    public static let checkboxCharacter = "\u{FFFC}"

    public enum Marker: Equatable {
        case bullet
        case checkbox
        /// A numbered item and the number it carries.
        case ordered(Int)
    }

    /// The marker a line begins with, if any.
    ///
    /// A number followed by a dot and a tab is only a marker when the number is
    /// short and actually a number — "1998.\tthe year" is prose, and a line
    /// starting with a fifteen-digit figure is not a list.
    public static func marker(of line: String) -> Marker? {
        if line.hasPrefix("•\t") { return .bullet }
        if line.hasPrefix(checkboxCharacter + "\t") { return .checkbox }
        guard let tab = line.firstIndex(of: "\t") else { return nil }
        let head = line[..<tab]
        guard head.hasSuffix("."), head.count <= 6,
              !head.dropLast().isEmpty, let number = Int(head.dropLast())
        else { return nil }
        return .ordered(number)
    }

    /// How many UTF-16 units the marker occupies, which is what the text system
    /// measures in. Zero when the line carries no marker.
    public static func markerLength(of line: String) -> Int {
        switch marker(of: line) {
        case .bullet, .checkbox:
            return 2
        case .ordered:
            guard let tab = line.firstIndex(of: "\t") else { return 0 }
            return (String(line[...tab]) as NSString).length
        case nil:
            return 0
        }
    }

    /// Whether anything but whitespace follows the marker.
    ///
    /// Pressing Return on an empty item ends the list rather than making
    /// another empty one, so this decides between continuing and stopping.
    public static func hasContentAfterMarker(_ line: String) -> Bool {
        let length = markerLength(of: line)
        guard length > 0 else { return !line.trimmingCharacters(in: .whitespaces).isEmpty }
        let ns = line as NSString
        guard ns.length > length else { return false }
        return !ns.substring(from: length).trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The marker text that continues a list after this line, or nil when the
    /// line has no marker to continue.
    public static func continuation(of line: String) -> Marker? {
        switch marker(of: line) {
        case .bullet: return .bullet
        case .checkbox: return .checkbox
        case .ordered(let n): return .ordered(n + 1)
        case nil: return nil
        }
    }

    /// Renumbers a run of ordered items so each level counts from where it
    /// started and restarts when the list is left.
    ///
    /// Each entry is an item's indent level and the number it currently shows;
    /// the result is the number it should show. A deeper level inherits nothing
    /// from a shallower one, and returning to a shallower level discards the
    /// deeper counters — "1, 1.1, 1.2, 2" rather than "1, 1.1, 1.2, 4".
    public static func renumber(_ items: [(level: Int, number: Int)]) -> [Int] {
        var counters: [Int: Int] = [:]
        return items.map { item in
            counters = counters.filter { $0.key <= item.level }
            let expected = counters[item.level].map { $0 + 1 } ?? item.number
            counters[item.level] = expected
            return expected
        }
    }

    /// Whether what has just been typed, followed by a space, should become an
    /// ordered-list marker.
    ///
    /// On a line that is already a list item, any number is accepted — the
    /// renumbering pass settles what it actually shows. On a plain line only
    /// "1." starts a list.
    ///
    /// That restriction is the difference between a note editor and a nuisance.
    /// Writing "1998. That was the year everything changed" is ordinary prose,
    /// and without the rule it silently became item 1998 of a list. CommonMark
    /// draws the line in the same place and for the same reason: an ordered
    /// list may only interrupt a paragraph when it starts at one.
    public static func startsOrderedList(_ typed: String, continuingExistingItem: Bool) -> Bool {
        guard typed.hasSuffix("."), typed.count <= 5 else { return false }
        let digits = typed.dropLast()
        guard !digits.isEmpty, let number = Int(digits) else { return false }
        return continuingExistingItem || number == 1
    }

    /// Whether pasted text is a web link worth turning into one.
    ///
    /// Deliberately narrow: a scheme this app will open, a host, and no spaces.
    /// Anything else is text the user meant to paste as text.
    public static func isWebLink(_ text: String) -> Bool {
        guard !text.contains(" "), let url = URL(string: text),
              let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }
}
