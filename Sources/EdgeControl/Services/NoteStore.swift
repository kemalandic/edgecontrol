import Foundation

/// Where notes live.
///
/// One folder, one file per note, plus an index and a history directory:
///
///     Notes/
///       index.json
///       <id>.rtf          the note, as real RTF
///       <id>.txt          plain mirror
///       History/<id>/20260920T174530Z.rtf
///
/// The body is written as RTF rather than the base64 the editor hands over so
/// the folder is worth something on its own: every note opens in TextEdit, and
/// Spotlight indexes the plain mirrors. A backup of this folder is a backup of
/// the notes, with no export step and nothing to decode.
///
/// Everything that decides anything lives in `NoteIndex`, `NoteHistoryPolicy`
/// and `NoteMigration`. What is left here is files.
public final class NoteStore: Sendable {

    private static var defaultDirectoryURL: URL {
        AppSupport.directory.appendingPathComponent("Notes", isDirectory: true)
    }

    private let directoryURL: URL
    private let policy: NoteHistoryPolicy

    /// `directory` exists so tests can point the store somewhere disposable.
    public init(directory: URL? = nil, policy: NoteHistoryPolicy = NoteHistoryPolicy()) {
        self.directoryURL = directory ?? Self.defaultDirectoryURL
        self.policy = policy
    }

    // MARK: - Paths

    private var indexURL: URL { directoryURL.appendingPathComponent("index.json") }
    private func bodyURL(_ id: String) -> URL { directoryURL.appendingPathComponent("\(id).rtf") }
    private func plainURL(_ id: String) -> URL { directoryURL.appendingPathComponent("\(id).txt") }
    private func historyURL(_ id: String) -> URL {
        directoryURL.appendingPathComponent("History/\(id)", isDirectory: true)
    }

    /// Compact, sortable, and legal in a filename on every filesystem the app
    /// might sit on — which rules out the colons in an ISO-8601 time.
    private static let stampFormat = "yyyyMMdd'T'HHmmss'Z'"

    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = stampFormat
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private static func date(fromStamp stamp: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = stampFormat
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: stamp)
    }

    // MARK: - Index

    public func index() -> NoteIndex {
        let decoder = JSONDecoder()
        // Must match `write`. A mismatch here does not fail loudly — it
        // returns an empty index, and an empty index reads as "no notes yet".
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: indexURL),
            let decoded = try? decoder.decode(NoteIndex.self, from: data)
        else { return NoteIndex() }
        return decoded
    }

    public func record(id: String) -> NoteRecord? { index()[id] }

    public func records() -> [NoteRecord] { index().mostRecentFirst }

    private func write(_ index: NoteIndex) {
        createDirectory(directoryURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(index) else {
            AppLog.persistence.error("encoding the note index failed")
            return
        }
        AppLog.attempt("writing the note index") {
            try data.write(to: indexURL, options: .atomic)
        }
    }

    // MARK: - Reading

    /// The note's body as base64 RTF, which is what the editor binds to.
    /// Empty when the note has no body on disk yet.
    public func body(id: String) -> String {
        guard let data = try? Data(contentsOf: bodyURL(id)) else { return "" }
        return data.base64EncodedString()
    }

    public func plainText(id: String) -> String {
        (try? String(contentsOf: plainURL(id), encoding: .utf8)) ?? ""
    }

    // MARK: - Writing

    /// Saves a note, archiving whatever it is replacing.
    ///
    /// - Parameter rtfBase64: the editor's own representation. An empty string
    ///   writes an empty note rather than deleting one; deleting is `delete`.
    public func save(id: String, rtfBase64: String, plainText: String, now: Date = Date()) {
        guard !id.isEmpty else { return }
        createDirectory(directoryURL)

        var index = self.index()
        archivePrevious(id: id, replacing: index[id], now: now)

        if let data = Data(base64Encoded: rtfBase64), !data.isEmpty {
            AppLog.attempt("writing note \(id)") {
                try data.write(to: bodyURL(id), options: .atomic)
            }
        } else {
            // A note emptied out keeps its file, as an empty one: a missing
            // file and an empty note are different things, and only one of
            // them should send the editor looking for a legacy body.
            AppLog.attempt("writing empty note \(id)") {
                try Data().write(to: bodyURL(id), options: .atomic)
            }
        }

        AppLog.attempt("writing note mirror \(id)") {
            try Data(plainText.utf8).write(to: plainURL(id), options: .atomic)
        }

        index.touch(id: id, title: NoteIndex.title(fromPlainText: plainText), at: now)
        write(index)
    }

    /// Registers a note the migration has just created, without disturbing a
    /// note that is already there.
    public func adopt(_ plan: NoteMigration.Plan, now: Date = Date()) {
        guard index()[plan.noteId] == nil else { return }
        save(id: plan.noteId, rtfBase64: plan.rtfBase64, plainText: plan.plainText, now: now)
    }

    public func delete(id: String) {
        var index = self.index()
        index.remove(id: id)
        write(index)
        let fm = FileManager.default
        for url in [bodyURL(id), plainURL(id), historyURL(id)] {
            guard fm.fileExists(atPath: url.path) else { continue }
            AppLog.attempt("removing \(url.lastPathComponent)") { try fm.removeItem(at: url) }
        }
    }

    // MARK: - History

    /// Stamps of the copies kept for a note, newest last.
    public func snapshots(id: String) -> [Date] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: historyURL(id).path) else { return [] }
        return
            names
            .filter { $0.hasSuffix(".rtf") }
            .compactMap { Self.date(fromStamp: String($0.dropLast(4))) }
            .sorted()
    }

    /// A past version's body, as base64 RTF, ready to hand back to the editor.
    public func snapshotBody(id: String, at stamp: Date) -> String? {
        let url = historyURL(id).appendingPathComponent("\(Self.stamp(stamp)).rtf")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return data.base64EncodedString()
    }

    private func archivePrevious(id: String, replacing record: NoteRecord?, now: Date) {
        guard let record, let previous = try? Data(contentsOf: bodyURL(id)), !previous.isEmpty else { return }

        let decision = policy.decide(existing: snapshots(id: id), outgoingModified: record.modified, now: now)
        guard !decision.changesNothing else { return }

        let directory = historyURL(id)
        if decision.archive != nil { createDirectory(directory) }

        if let stamp = decision.archive {
            AppLog.attempt("archiving note \(id)") {
                try previous.write(to: directory.appendingPathComponent("\(Self.stamp(stamp)).rtf"), options: .atomic)
            }
        }
        for stamp in decision.discard {
            let url = directory.appendingPathComponent("\(Self.stamp(stamp)).rtf")
            AppLog.attempt("pruning an archived copy of note \(id)") {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: -

    private func createDirectory(_ url: URL) {
        AppLog.attempt("creating \(url.lastPathComponent)") {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
