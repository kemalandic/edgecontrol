import Foundation
import Testing
@testable import EdgeControl

/// Disk and network both read counters that only climb, and both turn two
/// readings into a rate. That arithmetic used to live twice, with the sample
/// interval hardcoded into the divisor; this is it in one place, where a test
/// can reach it without a disk or a network interface.
@Suite("Byte rate")
struct ByteRateTests {

    // MARK: rate

    @Test("a rate is the delta over the interval")
    func plainRate() {
        #expect(ByteRate.perSecond(previous: 1_000, current: 3_000, elapsed: 2) == 1_000)
    }

    /// The reason this takes a measured interval instead of assuming one. The
    /// timers sampling these counters carry a 0.2s tolerance, so dividing by a
    /// hardcoded 2.0 reported every rate up to ten per cent low.
    @Test("the interval is the one that actually elapsed")
    func intervalMatters() {
        let overTwo = ByteRate.perSecond(previous: 0, current: 2_200, elapsed: 2.0)
        let overTwoPointTwo = ByteRate.perSecond(previous: 0, current: 2_200, elapsed: 2.2)
        #expect(overTwo == 1_100)
        // 2200 / 2.2 is not exactly 1000 in binary floating point.
        #expect(abs(overTwoPointTwo - 1_000) < 0.000_001)
        #expect(overTwo > overTwoPointTwo, "the shorter interval must report the higher rate")
    }

    /// A device reset or a counter wrap is not a burst of traffic. Reporting
    /// the difference would put a spike the width of the counter on the graph.
    @Test("a counter that went backwards reports nothing")
    func wrapReportsZero() {
        #expect(ByteRate.perSecond(previous: 5_000, current: 1_000, elapsed: 2) == 0)
        #expect(ByteRate.perSecond(previous: UInt64.max, current: 0, elapsed: 2) == 0)
    }

    @Test("an unchanged counter is a rate of zero, not a division artefact")
    func idleReportsZero() {
        #expect(ByteRate.perSecond(previous: 4_096, current: 4_096, elapsed: 2) == 0)
    }

    /// The first sample has no interval behind it, so there is nothing to
    /// divide by — and dividing anyway would be infinity on the graph.
    @Test("a non-positive interval reports zero", arguments: [0.0, -1.0])
    func noIntervalReportsZero(elapsed: TimeInterval) {
        #expect(ByteRate.perSecond(previous: 0, current: 1_000, elapsed: elapsed) == 0)
    }

    @Test("a very large delta stays finite")
    func largeDelta() {
        let rate = ByteRate.perSecond(previous: 0, current: UInt64(1) << 40, elapsed: 1)
        #expect(rate == Double(UInt64(1) << 40))
        #expect(rate.isFinite)
    }

    // MARK: elapsed

    @Test("elapsed seconds converts from nanoseconds")
    func elapsedConverts() {
        #expect(ByteRate.elapsedSeconds(since: 0, now: 2_500_000_000) == 2.5)
    }

    /// The first sample has no previous reading, and a monotonic clock never
    /// runs backwards — either way there is no interval.
    @Test("no forward movement means no interval", arguments: [(0 as UInt64, 0 as UInt64), (5_000, 1_000)])
    func noMovement(previous: UInt64, now: UInt64) {
        #expect(ByteRate.elapsedSeconds(since: previous, now: now) == 0)
    }

    // MARK: formatting

    @Test("each unit gets its own precision", arguments: [
        (512.0, "512 B/s"),
        (1_024.0, "1.0 KB/s"),
        (1_536.0, "1.5 KB/s"),
        (1_048_576.0, "1.0 MB/s"),
        (1_073_741_824.0, "1.00 GB/s"),
    ])
    func formatting(value: Double, expected: String) {
        #expect(ByteRate.formatted(value) == expected)
    }

    /// The boundaries are where an off-by-one shows up as "1024.0 KB/s".
    @Test("the unit changes exactly at the boundary")
    func boundaries() {
        #expect(ByteRate.formatted(1023).hasSuffix("B/s"))
        #expect(ByteRate.formatted(1023).contains("KB") == false)
        #expect(ByteRate.formatted(1024).contains("KB/s"))
        #expect(ByteRate.formatted(1024 * 1024 - 1).contains("KB/s"))
        #expect(ByteRate.formatted(1024 * 1024).contains("MB/s"))
    }

    @Test("zero formats as bytes, not an empty string")
    func zeroFormats() {
        #expect(ByteRate.formatted(0) == "0 B/s")
    }
}
