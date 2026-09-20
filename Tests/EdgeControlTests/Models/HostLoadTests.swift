import Foundation
import Testing
@testable import EdgeControl

@Suite("Host load")
struct HostLoadTests {

    private func ticks(user: UInt32 = 0, system: UInt32 = 0, idle: UInt32 = 0, nice: UInt32 = 0)
        -> HostLoad.CPUTicks {
        HostLoad.CPUTicks(user: user, system: system, idle: idle, nice: nice)
    }

    // MARK: cpu

    @Test("a half-idle interval reads as 50%")
    func halfBusy() {
        let percent = HostLoad.cpuPercent(previous: ticks(), current: ticks(user: 50, idle: 50))
        #expect(percent == 50)
    }

    @Test("a fully idle interval reads as zero, not as no reading")
    func fullyIdle() {
        #expect(HostLoad.cpuPercent(previous: ticks(), current: ticks(idle: 100)) == 0)
    }

    @Test("a fully busy interval reads as 100%")
    func fullyBusy() {
        #expect(HostLoad.cpuPercent(previous: ticks(), current: ticks(user: 100)) == 100)
    }

    /// nice time is work, not idle — a machine running a batch job at low
    /// priority is busy, and reporting it idle would hide exactly the load
    /// someone opens this dashboard to see.
    @Test("nice time counts as busy")
    func niceCountsAsBusy() {
        #expect(HostLoad.cpuPercent(previous: ticks(), current: ticks(idle: 50, nice: 50)) == 50)
    }

    @Test("system time counts as busy")
    func systemCountsAsBusy() {
        #expect(HostLoad.cpuPercent(previous: ticks(), current: ticks(system: 25, idle: 75)) == 25)
    }

    /// The reason this moved out of the service. The counters are UInt32 and
    /// the subtraction used to happen in UInt32 before converting to Double —
    /// at a hundred ticks a second that wraps in roughly 497 days, and
    /// subtracting past zero traps in Swift. A dashboard meant to stay up
    /// indefinitely should not have a date on it.
    @Test("a counter that wrapped yields no reading rather than trapping")
    func wrappedCounterIsRefused() {
        let previous = ticks(user: UInt32.max - 10, idle: 100)
        let current = ticks(user: 5, idle: 200)
        #expect(HostLoad.cpuPercent(previous: previous, current: current) == nil)
    }

    @Test("two identical readings yield no reading")
    func noTimePassed() {
        let same = ticks(user: 100, idle: 100)
        #expect(HostLoad.cpuPercent(previous: same, current: same) == nil)
    }

    @Test("the very first reading, against zeros, yields no reading")
    func firstReading() {
        #expect(HostLoad.cpuPercent(previous: ticks(), current: ticks()) == nil)
    }

    @Test("a reading near the top of the range still works")
    func nearMaximum() {
        let previous = ticks(user: UInt32.max - 100, idle: UInt32.max - 100)
        let current = ticks(user: UInt32.max - 50, idle: UInt32.max - 50)
        #expect(HostLoad.cpuPercent(previous: previous, current: current) == 50)
    }

    // MARK: storage

    private let gigabyte = Int64(1024 * 1024 * 1024)

    @Test("used is total minus available")
    func usedIsTotalMinusAvailable() throws {
        let snapshot = try #require(
            HostLoad.storage(totalBytes: 100 * gigabyte, availableBytes: 25 * gigabyte)
        )
        #expect(snapshot.totalGB == 100)
        #expect(snapshot.usedGB == 75)
        #expect(snapshot.usedPercent == 75)
    }

    @Test("a full disk reads as 100%")
    func fullDisk() throws {
        let snapshot = try #require(HostLoad.storage(totalBytes: 100 * gigabyte, availableBytes: 0))
        #expect(snapshot.usedPercent == 100)
    }

    @Test("an empty disk reads as 0%")
    func emptyDisk() throws {
        let snapshot = try #require(
            HostLoad.storage(totalBytes: 100 * gigabyte, availableBytes: 100 * gigabyte)
        )
        #expect(snapshot.usedPercent == 0)
        #expect(snapshot.usedGB == 0)
    }

    /// No disk means no percentage. The previous code divided by a 0.001 fudge
    /// factor, which turned a failed read into a confident-looking number.
    @Test("a total of zero yields nothing rather than a number")
    func zeroTotalYieldsNothing() {
        #expect(HostLoad.storage(totalBytes: 0, availableBytes: 0) == nil)
        #expect(HostLoad.storage(totalBytes: -1, availableBytes: 0) == nil)
    }

    /// volumeAvailableCapacityForImportantUsage counts space the system would
    /// free by purging, so it can exceed the raw total. Clamping keeps used
    /// from going negative.
    @Test("available above total does not drive used below zero")
    func availableAboveTotal() throws {
        let snapshot = try #require(
            HostLoad.storage(totalBytes: 100 * gigabyte, availableBytes: 150 * gigabyte)
        )
        #expect(snapshot.usedGB == 0)
        #expect(snapshot.usedPercent == 0)
    }

    @Test("negative available is treated as none")
    func negativeAvailable() throws {
        let snapshot = try #require(HostLoad.storage(totalBytes: 100 * gigabyte, availableBytes: -5))
        #expect(snapshot.usedPercent == 100)
    }
}
