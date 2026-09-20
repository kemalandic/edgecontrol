import Foundation
import IOKit

@MainActor
public final class DiskIOService: ObservableObject {
    @Published public var readBytesPerSec: Double = 0
    @Published public var writeBytesPerSec: Double = 0
    @Published public var readHistory: [Double] = []
    @Published public var writeHistory: [Double] = []

    /// Monotonic, so the rate is divided by the interval that actually
    /// elapsed rather than the one the timer was asked for.
    private var lastSampleNanos: UInt64 = 0
    private var previousRead: UInt64 = 0
    private var previousWrite: UInt64 = 0
    private var hasPrevious = false
    private var timer: Timer?
    private let maxHistory = 60

    public init() {}

    public func start() {
        stop()
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sample()
            }
        }
        timer?.tolerance = 0.2
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        let (read, write) = readDiskCounters()

        let nowNanos = DispatchTime.now().uptimeNanoseconds
        let elapsed = ByteRate.elapsedSeconds(since: lastSampleNanos, now: nowNanos)

        if hasPrevious {


            readBytesPerSec = ByteRate.perSecond(previous: previousRead, current: read, elapsed: elapsed)
            writeBytesPerSec = ByteRate.perSecond(previous: previousWrite, current: write, elapsed: elapsed)

            readHistory.append(readBytesPerSec)
            writeHistory.append(writeBytesPerSec)
            if readHistory.count > maxHistory { readHistory.removeFirst() }
            if writeHistory.count > maxHistory { writeHistory.removeFirst() }
        }

        lastSampleNanos = nowNanos
        previousRead = read
        previousWrite = write
        hasPrevious = true
    }

    /// Read cumulative disk I/O bytes via IOKit (no subprocess).
    private func readDiskCounters() -> (UInt64, UInt64) {
        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0

        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iter) == KERN_SUCCESS else {
            return (previousRead, previousWrite)
        }
        defer { IOObjectRelease(iter) }

        var disk = IOIteratorNext(iter)
        while disk != 0 {
            defer { IOObjectRelease(disk); disk = IOIteratorNext(iter) }

            var propsRef: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(disk, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = propsRef?.takeRetainedValue() as? [String: Any],
                  let stats = props["Statistics"] as? [String: Any] else { continue }

            if let read = stats["Bytes (Read)"] as? UInt64 { totalRead += read }
            if let write = stats["Bytes (Write)"] as? UInt64 { totalWrite += write }
        }

        return (totalRead, totalWrite)
    }

}
