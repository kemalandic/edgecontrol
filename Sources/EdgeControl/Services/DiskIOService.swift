import Foundation
import IOKit

@MainActor
public final class DiskIOService: ObservableObject {
    @Published public var readBytesPerSec: Double = 0
    @Published public var writeBytesPerSec: Double = 0
    @Published public var readHistory: [Double] = []
    @Published public var writeHistory: [Double] = []

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
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        let (read, write) = readDiskCounters()

        if hasPrevious {
            let deltaRead = read >= previousRead ? read - previousRead : 0
            let deltaWrite = write >= previousWrite ? write - previousWrite : 0
            readBytesPerSec = Double(deltaRead) / 2.0
            writeBytesPerSec = Double(deltaWrite) / 2.0

            readHistory.append(readBytesPerSec)
            writeHistory.append(writeBytesPerSec)
            if readHistory.count > maxHistory { readHistory.removeFirst() }
            if writeHistory.count > maxHistory { writeHistory.removeFirst() }
        }

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

    public static func formatSpeed(_ bytesPerSec: Double) -> String {
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
}
