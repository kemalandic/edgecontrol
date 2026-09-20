import Foundation

/// Turning raw process counters into what the Top Processes list shows.
///
/// Same shape as ByteRate: a total that only climbs, divided by the interval
/// that actually elapsed. Kept separate because the units and the guards differ
/// — a pid can be reused for a different process, which is not a wrap so much
/// as a different subject entirely.
public enum ProcessUsage {

    /// The share of a core's time a process used between two samples, as a
    /// percentage.
    ///
    /// Reports zero with no previous reading, with no elapsed time, and when
    /// the counter went backwards — the last of which means the pid now belongs
    /// to a different process, so the difference is meaningless rather than
    /// large.
    public static func cpuPercent(previous: UInt64, current: UInt64, elapsedNanos: UInt64) -> Double {
        guard elapsedNanos > 0, current >= previous else { return 0 }
        return (Double(current - previous) / Double(elapsedNanos)) * 100.0
    }

    /// The busiest `limit` processes, most CPU first.
    ///
    /// The tie-break is what makes this worth extracting. Swift's sort is not
    /// stable, and most of a process list sits at exactly zero per cent, so
    /// ordering on CPU alone let the bottom of the list reshuffle on every
    /// sample for no reason a viewer could see. Name then pid settles it.
    public static func busiest(_ processes: [ProcessInfo_EC], limit: Int) -> [ProcessInfo_EC] {
        guard limit > 0 else { return [] }
        return Array(
            processes
                .sorted {
                    if $0.cpuPercent != $1.cpuPercent { return $0.cpuPercent > $1.cpuPercent }
                    let byName = $0.name.localizedCaseInsensitiveCompare($1.name)
                    if byName != .orderedSame { return byName == .orderedAscending }
                    return $0.id < $1.id
                }
                .prefix(limit)
        )
    }
}
