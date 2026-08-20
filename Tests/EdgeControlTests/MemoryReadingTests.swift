import Darwin.Mach
import XCTest
@testable import EdgeControl

final class MemoryReadingTests: XCTestCase {
    private let pageSize: Double = 16384
    private let physicalBytes: Double = 137_438_953_472 // 128 GB

    /// Page counts read from `vm_stat` on a 128 GB machine that Activity Monitor
    /// and iStat Menus both reported as 63% used, 7% pressure.
    private func liveStats() -> vm_statistics64 {
        var stats = vm_statistics64()
        stats.free_count = 703_644
        stats.active_count = 3_580_256
        stats.inactive_count = 3_503_250
        stats.speculative_count = 75_851
        stats.wire_count = 425_874
        stats.purgeable_count = 316_230
        stats.external_page_count = 2_167_119
        stats.internal_page_count = 5_308_468 // anonymous 4,992,238 + purgeable
        stats.compressor_page_count = 39_382
        return stats
    }

    func testUsedMatchesActivityMonitor() {
        let reading = MemoryReading(stats: liveStats(), pageSize: pageSize, physicalBytes: physicalBytes)
        XCTAssertEqual(reading.usedGB, 83.3, accuracy: 0.1)
        XCTAssertEqual(reading.usedPercent, 65, accuracy: 1)
    }

    /// The bug this replaces: treating everything that was not free or speculative
    /// as used counted the file cache too, and reported 116 GB — 91% — on the very
    /// same sample. Anything above 70% here means the cache has crept back in.
    func testTheFileCacheIsNotCountedAsUsed() {
        let reading = MemoryReading(stats: liveStats(), pageSize: pageSize, physicalBytes: physicalBytes)
        XCTAssertLessThan(reading.usedPercent, 70)
        XCTAssertLessThan(reading.usedGB, 90)
    }

    func testPurgeablePagesComeOutOfAppMemory() {
        var stats = liveStats()
        let withPurgeable = MemoryReading(stats: stats, pageSize: pageSize, physicalBytes: physicalBytes)
        stats.purgeable_count = 0
        let withoutPurgeable = MemoryReading(stats: stats, pageSize: pageSize, physicalBytes: physicalBytes)
        XCTAssertEqual(
            withoutPurgeable.usedGB - withPurgeable.usedGB,
            316_230 * pageSize / (1024 * 1024 * 1024),
            accuracy: 0.001
        )
    }

    func testPressureCountsOnlyWiredAndCompressedPages() {
        let reading = MemoryReading(stats: liveStats(), pageSize: pageSize, physicalBytes: physicalBytes)
        XCTAssertEqual(reading.pressurePercent, 5.5, accuracy: 0.5)
    }

    /// Pressure and usage answer different questions. Filling the rest of the
    /// machine with reclaimable cache moves the gauge that reports usage and must
    /// leave the one that reports pressure where it was — the old formula moved
    /// both together, which is what left pressure pinned at 91%.
    func testPressureDoesNotFollowTheCache() {
        var stats = liveStats()
        let before = MemoryReading(stats: stats, pageSize: pageSize, physicalBytes: physicalBytes)
        stats.external_page_count += 700_000
        stats.free_count = 3_644
        stats.speculative_count = 0
        let after = MemoryReading(stats: stats, pageSize: pageSize, physicalBytes: physicalBytes)
        XCTAssertEqual(after.pressurePercent, before.pressurePercent, accuracy: 0.001)
        XCTAssertEqual(after.usedPercent, before.usedPercent, accuracy: 0.001)
    }

    func testPressureRisesWithCompressedPages() {
        var stats = liveStats()
        let calm = MemoryReading(stats: stats, pageSize: pageSize, physicalBytes: physicalBytes)
        stats.compressor_page_count = 2_000_000
        let strained = MemoryReading(stats: stats, pageSize: pageSize, physicalBytes: physicalBytes)
        XCTAssertGreaterThan(strained.pressurePercent, calm.pressurePercent + 20)
    }

    func testPercentagesStayInRange() {
        var stats = vm_statistics64()
        stats.wire_count = 90_000_000 // more pages than the machine has
        stats.internal_page_count = 90_000_000
        let reading = MemoryReading(stats: stats, pageSize: pageSize, physicalBytes: physicalBytes)
        XCTAssertEqual(reading.usedPercent, 100)
        XCTAssertEqual(reading.pressurePercent, 100)
    }

    /// `purgeable_count` can exceed `internal_page_count` between the two reads
    /// inside the kernel's snapshot, and a negative page count would run the
    /// gauge backwards.
    func testMorePurgeableThanInternalPagesReadsAsZeroAppMemory() {
        var stats = vm_statistics64()
        stats.internal_page_count = 1_000
        stats.purgeable_count = 5_000
        let reading = MemoryReading(stats: stats, pageSize: pageSize, physicalBytes: physicalBytes)
        XCTAssertEqual(reading.usedGB, 0)
        XCTAssertEqual(reading.usedPercent, 0)
    }

    func testAZeroPhysicalSizeDoesNotProduceNaN() {
        let reading = MemoryReading(stats: liveStats(), pageSize: pageSize, physicalBytes: 0)
        XCTAssertEqual(reading.usedPercent, 0)
        XCTAssertEqual(reading.pressurePercent, 0)
        XCTAssertEqual(reading.usedGB, 0)
    }
}
