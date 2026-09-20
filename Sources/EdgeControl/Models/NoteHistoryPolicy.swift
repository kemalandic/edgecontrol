import Foundation

/// How much of a note's past to keep, and when to take a copy.
///
/// The editor saves on a debounce, so a person typing a paragraph produces
/// dozens of saves a minute. Archiving each one would fill the disk with
/// keystroke-sized differences and bury the version anyone would actually want
/// to go back to. So copies are coalesced: at most one per window, and what
/// gets copied is the version being *replaced* — a snapshot is a way back, and
/// a way back to the text already on screen is no use.
public struct NoteHistoryPolicy: Sendable, Equatable {
    /// At most one archived copy per window.
    public var coalescingWindow: TimeInterval
    /// How many copies to keep. Zero turns history off.
    public var keep: Int

    public init(coalescingWindow: TimeInterval = 600, keep: Int = 20) {
        self.coalescingWindow = coalescingWindow
        self.keep = keep
    }

    public struct Decision: Sendable, Equatable {
        /// Stamp to archive the outgoing version under, or nil to keep none.
        public var archive: Date?
        /// Copies to delete, oldest first.
        public var discard: [Date]

        public var changesNothing: Bool { archive == nil && discard.isEmpty }
    }

    /// - Parameters:
    ///   - existing: stamps of the copies already on disk, in any order.
    ///   - outgoingModified: when the version now being replaced was written.
    ///   - now: the time of this save.
    public func decide(existing: [Date], outgoingModified: Date, now: Date) -> Decision {
        let sorted = existing.sorted()

        // History off: keep nothing, and clear out anything a previous
        // setting left behind.
        guard keep > 0 else { return Decision(archive: nil, discard: sorted) }

        // Still inside the window of the newest copy, or a copy already
        // carries this exact stamp — either way there is nothing to add.
        let withinWindow = sorted.last.map { now.timeIntervalSince($0) < coalescingWindow } ?? false
        var archive: Date? = (withinWindow || sorted.contains(outgoingModified)) ? nil : outgoingModified

        var all = sorted
        if let archive { all.append(archive) }
        all.sort()

        var discard = Array(all.prefix(max(0, all.count - keep)))

        // A copy that would be pruned in the same breath is not worth writing.
        if let stamp = archive, discard.contains(stamp) {
            discard.removeAll { $0 == stamp }
            archive = nil
        }

        return Decision(archive: archive, discard: discard)
    }
}
