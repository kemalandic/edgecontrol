import Foundation

/// What the index knows about one note without opening it.
///
/// The body is RTF in a file of its own; this is the part that has to be cheap
/// to read, because listing notes, naming them in a picker and finding the one
/// a widget points at all happen far more often than editing one.
public struct NoteRecord: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public var title: String
    public var created: Date
    public var modified: Date

    public init(id: String, title: String, created: Date, modified: Date) {
        self.id = id
        self.title = title
        self.created = created
        self.modified = modified
    }
}

/// The note index: every note the app knows about, by id.
///
/// Kept as a dictionary on disk so a note can be found by id without a scan,
/// and handed out as a sorted array so the order a person sees never depends
/// on dictionary iteration.
public struct NoteIndex: Codable, Sendable, Equatable {
    public private(set) var notes: [String: NoteRecord]

    public init(notes: [String: NoteRecord] = [:]) {
        self.notes = notes
    }

    public subscript(id: String) -> NoteRecord? { notes[id] }

    public var isEmpty: Bool { notes.isEmpty }
    public var count: Int { notes.count }

    /// Most recently edited first, and by id where two notes were saved in the
    /// same instant — a stable order, so a list does not reshuffle under the
    /// cursor when two notes share a timestamp.
    public var mostRecentFirst: [NoteRecord] {
        notes.values.sorted {
            if $0.modified != $1.modified { return $0.modified > $1.modified }
            return $0.id < $1.id
        }
    }

    public mutating func upsert(_ record: NoteRecord) {
        notes[record.id] = record
    }

    /// Records the edit: the title follows the text, `created` never moves.
    public mutating func touch(id: String, title: String, at date: Date) {
        if var existing = notes[id] {
            existing.title = title
            existing.modified = date
            notes[id] = existing
        } else {
            notes[id] = NoteRecord(id: id, title: title, created: date, modified: date)
        }
    }

    @discardableResult
    public mutating func remove(id: String) -> NoteRecord? {
        notes.removeValue(forKey: id)
    }

    // MARK: - Titles

    /// What to call a note, given its plain text.
    ///
    /// The first line that says something, with any list or heading markup
    /// stripped off the front — a note that opens with "- [ ] call the bank"
    /// is called "call the bank", not "☐ call the bank". Long first lines are
    /// cut on a word boundary so a title never ends mid-word.
    public static func title(fromPlainText text: String, fallback: String = "Untitled note") -> String {
        for rawLine in text.components(separatedBy: .newlines) {
            let line = strippingMarkup(rawLine).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            return truncated(line)
        }
        return fallback
    }

    /// Drops a leading bullet, checkbox or number, and any run of heading
    /// hashes. Heading markup is not in the stored text — the editor converts
    /// it as it is typed — but notes written before that, and notes pasted in
    /// as markdown, still carry it.
    private static func strippingMarkup(_ line: String) -> String {
        var text = line
        let markerLength = StickyNoteMarkup.markerLength(of: text)
        if markerLength > 0 {
            text = (text as NSString).substring(from: markerLength)
        }
        var stripped = Substring(text)
        var hashes = 0
        while stripped.first == "#", hashes < 6 {
            stripped = stripped.dropFirst()
            hashes += 1
        }
        return hashes > 0 ? String(stripped) : text
    }

    private static let titleLimit = 60

    private static func truncated(_ line: String) -> String {
        guard line.count > titleLimit else { return line }
        let cut = line.prefix(titleLimit)
        if let lastSpace = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: lastSpace) > 20 {
            return String(cut[..<lastSpace]) + "…"
        }
        return String(cut) + "…"
    }
}
