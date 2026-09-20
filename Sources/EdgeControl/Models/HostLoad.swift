import Foundation

/// The arithmetic behind the CPU and storage gauges, kept apart from the calls
/// that read the host.
public enum HostLoad {

    /// A reading of the kernel's cumulative CPU tick counters.
    public struct CPUTicks: Equatable, Sendable {
        public let user: UInt32
        public let system: UInt32
        public let idle: UInt32
        public let nice: UInt32

        public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
            self.user = user
            self.system = system
            self.idle = idle
            self.nice = nice
        }
    }

    /// Busy percentage between two tick readings, or nil when the pair says
    /// nothing — no time passed, or a counter went backwards.
    ///
    /// The counters are UInt32, and the subtraction used to happen in UInt32
    /// before the conversion to Double. Those counters wrap: at a hundred ticks
    /// a second a UInt32 comes round in roughly 497 days, and subtracting past
    /// zero traps in Swift rather than wrapping quietly. A dashboard that is
    /// meant to stay up indefinitely should not have a date on it.
    public static func cpuPercent(previous: CPUTicks, current: CPUTicks) -> Double? {
        func delta(_ now: UInt32, _ before: UInt32) -> Double? {
            now >= before ? Double(now - before) : nil
        }
        guard let user = delta(current.user, previous.user),
            let system = delta(current.system, previous.system),
            let idle = delta(current.idle, previous.idle),
            let nice = delta(current.nice, previous.nice)
        else { return nil }

        let total = user + system + idle + nice
        guard total > 0 else { return nil }
        return ((user + system + nice) / total) * 100
    }

    /// What the storage gauge shows.
    public struct StorageSnapshot: Equatable, Sendable {
        public let usedPercent: Double
        public let usedGB: Double
        public let totalGB: Double
    }

    /// Used share of a volume, from its total and what is available.
    ///
    /// Returns nil for a total of zero rather than dividing by a fudge factor:
    /// there is no such thing as a percentage of no disk, and reporting one
    /// hides the failed read that produced it.
    public static func storage(totalBytes: Int64, availableBytes: Int64) -> StorageSnapshot? {
        guard totalBytes > 0 else { return nil }
        let gigabyte = 1024.0 * 1024 * 1024
        let clampedAvailable = min(max(availableBytes, 0), totalBytes)
        let totalGB = Double(totalBytes) / gigabyte
        let usedGB = Double(totalBytes - clampedAvailable) / gigabyte
        return StorageSnapshot(
            usedPercent: min(max(usedGB / totalGB * 100, 0), 100),
            usedGB: usedGB,
            totalGB: totalGB
        )
    }
}
