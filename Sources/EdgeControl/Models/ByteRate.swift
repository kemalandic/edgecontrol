import Foundation

/// Turning a pair of cumulative byte counters into a rate, and a rate into text.
///
/// Disk and network both read counters that only climb until the device or the
/// interface resets them, and both turned two readings into bytes per second
/// with the sample interval written into the divisor by hand — `/ 2.0`, in two
/// files, disconnected from the `2.0` in the timer beside it. The timers also
/// carry a 0.2s tolerance, so the interval was never exactly two seconds and
/// every rate was reported up to ten per cent low before anything went wrong.
///
/// Measuring the interval instead of assuming it costs nothing and removes a
/// class of silent error: changing a timer can no longer change what the
/// numbers mean.
public enum ByteRate {

    /// Bytes per second between two cumulative readings.
    ///
    /// A counter that went backwards means a reset or a wrap, not a sudden
    /// burst of traffic, so it reports zero rather than an enormous spike. A
    /// non-positive interval reports zero too, rather than dividing by it.
    public static func perSecond(previous: UInt64, current: UInt64, elapsed: TimeInterval) -> Double {
        guard elapsed > 0, current >= previous else { return 0 }
        return Double(current - previous) / elapsed
    }

    /// "3.5 KB/s" and friends. One implementation; it existed twice, byte for
    /// byte, and one of the two copies had no callers at all.
    public static func formatted(_ bytesPerSec: Double) -> String {
        if bytesPerSec < 1024 {
            return String(format: "%.0f B/s", bytesPerSec)
        } else if bytesPerSec < 1024 * 1024 {
            return String(format: "%.1f KB/s", bytesPerSec / 1024)
        } else if bytesPerSec < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB/s", bytesPerSec / (1024 * 1024))
        } else {
            return String(format: "%.2f GB/s", bytesPerSec / (1024 * 1024 * 1024))
        }
    }

    /// Monotonic seconds since a previous reading, for callers measuring their
    /// own sample interval. Wall-clock time would let an NTP step turn one
    /// sample into a nonsense rate.
    public static func elapsedSeconds(since previous: UInt64, now: UInt64 = DispatchTime.now().uptimeNanoseconds) -> TimeInterval {
        guard now > previous else { return 0 }
        return Double(now - previous) / 1_000_000_000
    }
}
