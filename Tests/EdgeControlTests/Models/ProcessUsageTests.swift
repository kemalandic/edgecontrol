import Foundation
import Testing
@testable import EdgeControl

@Suite("Process usage")
struct ProcessUsageTests {

    private func proc(_ pid: Int32, _ name: String, cpu: Double) -> ProcessInfo_EC {
        ProcessInfo_EC(id: pid, name: name, cpuPercent: cpu, memoryMB: 0, icon: nil)
    }

    // MARK: cpu percent

    @Test("a process using a full core for the whole interval reads as 100%")
    func fullCore() {
        let second: UInt64 = 1_000_000_000
        #expect(ProcessUsage.cpuPercent(previous: 0, current: second, elapsedNanos: second) == 100)
    }

    @Test("half a core reads as 50%")
    func halfCore() {
        let second: UInt64 = 1_000_000_000
        #expect(ProcessUsage.cpuPercent(previous: 0, current: second / 2, elapsedNanos: second) == 50)
    }

    /// A pid outliving one sample and being handed to a different process is
    /// normal. The counter appears to jump backwards, and the difference means
    /// nothing rather than meaning a lot.
    @Test("a counter that went backwards reads as zero")
    func reusedPidReadsZero() {
        #expect(ProcessUsage.cpuPercent(previous: 5_000, current: 100, elapsedNanos: 1_000) == 0)
    }

    @Test("no elapsed time reads as zero rather than dividing by it")
    func noIntervalReadsZero() {
        #expect(ProcessUsage.cpuPercent(previous: 0, current: 1_000, elapsedNanos: 0) == 0)
    }

    @Test("an idle process reads as zero")
    func idleReadsZero() {
        #expect(ProcessUsage.cpuPercent(previous: 900, current: 900, elapsedNanos: 1_000) == 0)
    }

    /// Multi-core machines let a process use more than one core's worth, so the
    /// figure is deliberately not clamped at 100.
    @Test("a process on several cores can exceed 100%")
    func multiCoreExceedsOneHundred() {
        let second: UInt64 = 1_000_000_000
        #expect(ProcessUsage.cpuPercent(previous: 0, current: second * 3, elapsedNanos: second) == 300)
    }

    // MARK: busiest

    @Test("the list is ordered by CPU, busiest first")
    func orderedByCPU() {
        let top = ProcessUsage.busiest(
            [
                proc(1, "idle", cpu: 0), proc(2, "busy", cpu: 80), proc(3, "some", cpu: 12),
            ], limit: 10)
        #expect(top.map(\.name) == ["busy", "some", "idle"])
    }

    @Test("the list is cut to the limit")
    func cutToLimit() {
        let many = (1...30).map { proc(Int32($0), "p\($0)", cpu: Double($0)) }
        #expect(ProcessUsage.busiest(many, limit: 16).count == 16)
        #expect(ProcessUsage.busiest(many, limit: 16).first?.cpuPercent == 30)
    }

    /// The reason this is not a bare sorted(by:). Swift's sort is not stable
    /// and most of a process list sits at exactly zero, so ordering on CPU
    /// alone let the bottom of the widget reshuffle on every sample.
    @Test("processes tied on CPU keep a settled order")
    func tiesAreStable() {
        let unsorted = [
            proc(9, "zebra", cpu: 0), proc(3, "apple", cpu: 0),
            proc(7, "mango", cpu: 0), proc(1, "busy", cpu: 50),
        ]
        let once = ProcessUsage.busiest(unsorted, limit: 10)
        let again = ProcessUsage.busiest(unsorted.reversed(), limit: 10)
        #expect(once.map(\.name) == ["busy", "apple", "mango", "zebra"])
        #expect(once.map(\.id) == again.map(\.id), "the order changed with the input order")
    }

    @Test("two processes with the same name are separated by pid")
    func sameNameSeparatedByPid() {
        let top = ProcessUsage.busiest(
            [
                proc(42, "helper", cpu: 0), proc(7, "helper", cpu: 0),
            ], limit: 10)
        #expect(top.map(\.id) == [7, 42])
    }

    @Test("a limit of zero or less yields nothing", arguments: [0, -1])
    func nonPositiveLimit(limit: Int) {
        #expect(ProcessUsage.busiest([proc(1, "p", cpu: 1)], limit: limit).isEmpty)
    }

    @Test("fewer processes than the limit returns all of them")
    func fewerThanLimit() {
        #expect(ProcessUsage.busiest([proc(1, "p", cpu: 1)], limit: 16).count == 1)
    }
}
